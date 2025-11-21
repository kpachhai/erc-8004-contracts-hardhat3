#!/usr/bin/env bash
set -euo pipefail

# generate_metadata_bundle.sh
#
# A generalized script to generate inline metadata.json bundles for manual verification.
#
# USAGE: ./generate_metadata_bundle.sh [ContractName1] [ContractName2] ...

OUT_BASE="verify-bundles"
ARTIFACTS_DIR="artifacts"
BUILD_INFO_DIR="artifacts/build-info"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }
need jq

to_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }

npm_key_to_node_modules() {
  local key="$1"
  local rest="${key#npm/}"
  if [[ "$rest" == @* ]]; then
    local scope="$(cut -d/ -f1 <<<"$rest")"
    local pkg_ver="$(cut -d/ -f2 <<<"$rest")"
    local path="$(cut -d/ -f3- <<<"$rest")"
    local pkg="${pkg_ver%@*}"
    echo "node_modules/$scope/$pkg/$path"
  else
    local pkg_ver="$(cut -d/ -f1 <<<"$rest")"
    local path="$(cut -d/ -f2- <<<"$rest")"
    local pkg="${pkg_ver%@*}"
    echo "node_modules/$pkg/$path"
  fi
}

resolve_local_source() {
  local key="$1"
  local cand

  if [[ "$key" == npm/* ]]; then
    cand="$(npm_key_to_node_modules "$key")"
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  fi
  if [[ "$key" == @* ]] || [[ "$key" != */* ]]; then
    cand="node_modules/$key"
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  fi
  if [ -f "$key" ]; then echo "$key"; return 0; fi
  for root in contracts src lib node_modules; do
    cand="$root/$key"
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  done
  if [[ "$key" == */contracts/* ]]; then
    cand="contracts/${key#*/contracts/}"
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  fi
  if [[ "$key" == */src/* ]]; then
    cand="src/${key#*/src/}"
    [ -f "$cand" ] && { echo "$cand"; return 0; }
  fi
  
  # Recursive fallback
  local basename
  basename=$(basename "$key")
  cand=$(find . -type f -name "$basename" -not -path "*/node_modules/*" -not -path "*/artifacts/*" | head -n 1)
  if [ -n "$cand" ] && [ -f "$cand" ]; then echo "$cand"; return 0; fi

  return 1
}

find_build_info_file() {
  local name="$1"
  
  # Strategy 1: .dbg.json (Legacy/Standard Hardhat)
  local dbg_file
  dbg_file="$(find "$ARTIFACTS_DIR" -type f -name "${name}.dbg.json" -print -quit)"

  if [ -n "$dbg_file" ]; then
    local bi_hash
    bi_hash="$(jq -r '.buildInfo.id // empty' "$dbg_file" 2>/dev/null || true)"
    if [ -n "$bi_hash" ]; then
      local candidate="$BUILD_INFO_DIR/${bi_hash}.json"
      if [ -f "$candidate" ]; then echo "$candidate"; return 0; fi
    fi
  fi

  # Strategy 2: Scan build-info directory (Hardhat v3 / Pruned artifacts)
  # We grep first for speed, then use jq to confirm the exact contract definition exists.
  local candidates
  candidates="$(grep -l "\"$name\"" "$BUILD_INFO_DIR"/*.json 2>/dev/null || true)"
  
  for f in $candidates; do
    # BUGFIX: We must use 'any' to check all entries. 
    # Previously, iterating with 'to_entries[]' caused failure if the last file checked didn't have the contract.
    if jq -e --arg n "$name" '
      (.output.contracts // .contracts) | to_entries | any(.value | has($n))
    ' "$f" >/dev/null 2>&1; then
      echo "$f"
      return 0
    fi
  done

  return 1
}

if [ ! -d "$ARTIFACTS_DIR" ]; then
  die "Directory '$ARTIFACTS_DIR' not found. Run: npx hardhat compile"
fi

mkdir -p "$OUT_BASE"
MANIFEST="$OUT_BASE/MANIFEST.txt"

# Append mode if file exists, else create
if [ ! -f "$MANIFEST" ]; then
    echo "HashScan Verify Upload Guide" > "$MANIFEST"
    echo "============================" >> "$MANIFEST"
    echo "" >> "$MANIFEST"
fi

echo "== Generating Metadata Bundles =="

for CONTRACT_NAME in "$@"; do
  echo ""
  echo "Processing: $CONTRACT_NAME"

  if ! BI_FILE="$(find_build_info_file "$CONTRACT_NAME")"; then
    echo "  ! FAIL: Build-info not found for '$CONTRACT_NAME'."
    echo "    This usually means Hardhat's incremental cache is out of sync."
    echo "    [FIX] Please run: npx hardhat clean && npx hardhat compile"
    continue
  fi
  echo "  • Found build-info: $BI_FILE"

  META_JSON="$(jq -r --arg n "$CONTRACT_NAME" '
    [ (.output.contracts // .contracts) | to_entries[] | .value[$n].metadata // empty ] | first
  ' "$BI_FILE")"

  if [ -z "$META_JSON" ] || [ "$META_JSON" = "null" ]; then
    echo "  ! FAIL: Metadata object not found inside build-info."
    echo "    [FIX] Run: npx hardhat clean && npx hardhat compile"
    continue
  fi

  CONTRACT_DIR="$OUT_BASE/$CONTRACT_NAME"
  mkdir -p "$CONTRACT_DIR"
  OUT_FILE="$CONTRACT_DIR/metadata.json"
  
  echo "$META_JSON" | jq . > "$OUT_FILE"
  echo "  • Inlining source code..."
  
  SOURCE_KEYS="$(jq -r '.sources | keys[]' "$OUT_FILE")"
  MISSING_COUNT=0

  while IFS= read -r key; do
    [ -z "$key" ] && continue
    if [ "$(jq -r --arg k "$key" '(.sources[$k].content != null)' "$OUT_FILE")" = "true" ]; then
        tmp=$(mktemp)
        jq --arg k "$key" '(.sources[$k] |= del(.urls))' "$OUT_FILE" > "$tmp" && mv "$tmp" "$OUT_FILE"
        continue
    fi
    if local_path="$(resolve_local_source "$key")"; then
      tmp=$(mktemp)
      jq --arg k "$key" --rawfile c "$local_path" '(.sources[$k].content = $c) | (.sources[$k] |= del(.urls))' "$OUT_FILE" > "$tmp" && mv "$tmp" "$OUT_FILE"
    else
      echo "    ! WARNING: Local source not found: $key"
      MISSING_COUNT=$((MISSING_COUNT + 1))
    fi
  done <<< "$SOURCE_KEYS"

  STATUS="OK"
  [ "$MISSING_COUNT" -gt 0 ] && STATUS="WARNINGS ($MISSING_COUNT missing sources)"
  echo "  -> $STATUS"

  ENV_VAR_NAME="$(to_upper "${CONTRACT_NAME}")_ADDRESS"
  ADDRESS_VAL="${!ENV_VAR_NAME:-}"
  [ -z "$ADDRESS_VAL" ] && ADDRESS_VAL="<set env $ENV_VAR_NAME>"

  {
    echo "- $CONTRACT_NAME"
    echo "  File: $OUT_FILE"
    echo "  Address: $ADDRESS_VAL"
    CTOR_ARGS=$(jq -r 'try (.output.abi[] | select(.type == "constructor").inputs) catch []' "$OUT_FILE")
    if [ -n "$CTOR_ARGS" ] && [ "$CTOR_ARGS" != "[]" ] && [ "$CTOR_ARGS" != "null" ]; then
        echo "  Constructor args required:"
        echo "$CTOR_ARGS" | jq -r '.[] | "    \(.name) (\(.type))"' 
    fi
    echo ""
  } >> "$MANIFEST"
done

echo ""
echo "Done. Open $MANIFEST"