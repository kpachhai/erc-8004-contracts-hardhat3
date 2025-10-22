#!/usr/bin/env bash
set -euo pipefail

# make_sourcify_inline_metadata.sh (Hardhat v3)
# Generate inline metadata.json bundles (all sources embedded) for HashScan/Sourcify manual verification.
# Produces metadata for:
# - IdentityRegistryUpgradeable (implementation)
# - ReputationRegistryUpgradeable (implementation)
# - ValidationRegistryUpgradeable (implementation)
# - ERC1967Proxy (one metadata usable for all 3 proxies)
#
# No Foundry dependency. Reads Hardhat build-info via the *.dbg.json pointers in artifacts/.
#
# Output:
#   verify-bundles/
#     identity-impl/metadata.json
#     reputation-impl/metadata.json
#     validation-impl/metadata.json
#     proxy/metadata.json
#     MANIFEST.txt
#
# Inputs (optional but recommended for MANIFEST and proxy constructor args):
#   export ID_IMPL=0x...
#   export REP_IMPL=0x...
#   export VAL_IMPL=0x...
#   export ID_PROXY=0x...
#   export REP_PROXY=0x...
#   export VAL_PROXY=0x...
#
# Usage:
#   # After "npx hardhat compile"
#   ./make_sourcify_inline_metadata.sh
#
# Then go to each contract on https://hashscan.io/, click "Verify", and upload the corresponding metadata.json.

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

need jq

# Addresses (optional; used in manifest and proxy constructor args)
ID_IMPL="${ID_IMPL:-}"
REP_IMPL="${REP_IMPL:-}"
VAL_IMPL="${VAL_IMPL:-}"
ID_PROXY="${ID_PROXY:-}"
REP_PROXY="${REP_PROXY:-}"
VAL_PROXY="${VAL_PROXY:-}"

# Source paths (as they appear to solc in build-info)
SRC_ID="${SRC_ID:-contracts/IdentityRegistryUpgradeable.sol}"
SRC_REP="${SRC_REP:-contracts/ReputationRegistryUpgradeable.sol}"
SRC_VAL="${SRC_VAL:-contracts/ValidationRegistryUpgradeable.sol}"
# Prefer your local proxy under contracts/. If you don't have one, we will auto-discover from build-info.
SRC_PROXY_DEFAULT="${SRC_PROXY:-contracts/ERC1967Proxy.sol}"

NAME_ID="${NAME_ID:-IdentityRegistryUpgradeable}"
NAME_REP="${NAME_REP:-ReputationRegistryUpgradeable}"
NAME_VAL="${NAME_VAL:-ValidationRegistryUpgradeable}"
NAME_PROXY="${NAME_PROXY:-ERC1967Proxy}"

OUT_BASE="verify-bundles"
BUILD_INFO_DIR="artifacts/build-info"
ARTIFACTS_DIR="artifacts"

[ -d "$ARTIFACTS_DIR" ] || die "Hardhat artifacts/ not found. Run: npx hardhat compile"

mkdir -p "$OUT_BASE"

# Lowercase (POSIX-safe; no Bash 4 ${var,,})
to_lower() { tr 'A-Z' 'a-z' <<<"$1"; }

trim_end_slash() { local s="$1"; while [ "${s%/}" != "$s" ]; do s="${s%/}"; done; printf "%s" "$s"; }

# Resolve build-info path from the Hardhat debug artifact
build_info_from_dbg() {
  # $1 = source path (contracts/...), $2 = contract name
  local src="$1" name="$2"
  local dbg1="$ARTIFACTS_DIR/$src/${name}.dbg.json"
  local dbg2="$ARTIFACTS_DIR/contracts/$src/${name}.dbg.json"
  local dbg=""
  if [ -f "$dbg1" ]; then dbg="$dbg1"
  elif [ -f "$dbg2" ]; then dbg="$dbg2"
  else
    dbg="$(find "$ARTIFACTS_DIR" -type f -name "${name}.dbg.json" 2>/dev/null | while read -r f; do
      local srcName
      srcName="$(jq -r '.sourceName // .sourcePath // empty' "$f" 2>/dev/null || true)"
      if [ -n "$srcName" ] && [ "$srcName" = "$src" ]; then echo "$f"; break; fi
    done || true)"
  fi
  [ -n "$dbg" ] && [ -f "$dbg" ] || return 1

  local bi
  bi="$(jq -r '.buildInfo.path // empty' "$dbg" 2>/dev/null || true)"
  [ -n "$bi" ] && [ -f "$bi" ] && { echo "$bi"; return 0; }

  local hash
  hash="$(jq -r '.buildInfo.id // empty' "$dbg" 2>/dev/null || true)"
  if [ -n "$hash" ] && [ -f "$BUILD_INFO_DIR/${hash}.json" ]; then
    echo "$BUILD_INFO_DIR/${hash}.json"
    return 0
  fi
  return 1
}

# Extract canonical metadata JSON for (src, name) into $out
extract_metadata_to() {
  # $1 = source path, $2 = contract name, $3 = out_metadata
  local src="$1" name="$2" out="$3"
  local bi
  if bi="$(build_info_from_dbg "$src" "$name")"; then :; else
    # Fallback: search build-info files
    bi="$(find "$BUILD_INFO_DIR" -type f -name "*.json" | head -n1 || true)"
  fi
  [ -n "$bi" ] && [ -f "$bi" ] || return 1

  # Try direct look-up with known src key
  local meta
  meta="$(jq -r --arg s "$src" --arg n "$name" '.output.contracts[$s][$n].metadata // empty' "$bi")"
  if [ -z "$meta" ] || [ "$meta" = "null" ]; then
    # Search for first occurrence by contract name across sources
    meta="$(jq -r --arg n "$name" '
      .output.contracts
      | to_entries[]
      | .value[$n].metadata // empty
    ' "$bi" | awk 'NF{print; exit}')"
  fi
  [ -n "$meta" ] && [ "$meta" != "null" ] || return 1

  printf "%s" "$meta" | jq . > "$out"
  return 0
}

# Map metadata key like:
#   npm/@openzeppelin/contracts@5.4.0/utils/Address.sol
# to a local file path:
#   node_modules/@openzeppelin/contracts/utils/Address.sol
npm_key_to_node_modules() {
  # $1 = key starting with npm/
  local key="$1"
  local rest="${key#npm/}"
  local pkg="" rel=""

  if [[ "$rest" == @* ]]; then
    # Scoped: @scope/package@version/path...
    local scope part2
    scope="$(cut -d/ -f1 <<<"$rest")"                  # @openzeppelin
    part2="$(cut -d/ -f2 <<<"$rest")"                  # contracts@5.4.0
    local pkg_base="${part2%@*}"                       # contracts
    pkg="$scope/$pkg_base"                             # @openzeppelin/contracts
    rel="$(cut -d/ -f3- <<<"$rest")"                   # utils/Address.sol
  else
    # Unscoped: package@version/path...
    local first
    first="$(cut -d/ -f1 <<<"$rest")"                  # solmate@...
    pkg="${first%@*}"                                  # solmate
    rel="$(cut -d/ -f2- <<<"$rest")"                   # src/...
  fi

  if [ -n "$pkg" ] && [ -n "$rel" ]; then
    echo "node_modules/$pkg/$rel"
    return 0
  fi
  return 1
}

# Resolve a metadata.sources key to a local filesystem path
resolve_local_source() {
  # $1 = key path as in metadata
  local key="$1" cand rest
  # 1) npm/… keys (Hardhat v3 writes version-pinned npm source keys)
  if [[ "$key" == npm/* ]]; then
    if cand="$(npm_key_to_node_modules "$key")" && [ -f "$cand" ]; then
      echo "$cand"; return 0
    fi
  fi
  # 2) node_modules for @-scoped or unscoped imports
  if [[ "$key" == @* ]] || [[ "$key" != */* ]]; then
    cand="node_modules/$key"; [ -f "$cand" ] && { echo "$cand"; return 0; }
  fi
  # 3) project-relative
  cand="$key"; [ -f "$cand" ] && { echo "$cand"; return 0; }
  # 4) common roots
  for root in contracts src lib node_modules; do
    cand="$root/$key"; [ -f "$cand" ] && { echo "$cand"; return 0; }
  done
  # 5) strip to contracts/ or src/
  case "$key" in
    */contracts/*)
      rest="${key#*/contracts/}"
      for root in contracts src; do
        cand="$root/$rest"; [ -f "$cand" ] && { echo "$cand"; return 0; }
      done
      ;;
  esac
  case "$key" in
    */src/*)
      rest="${key#*/src/}"
      for root in src contracts; do
        cand="$root/$rest"; [ -f "$cand" ] && { echo "$cand"; return 0; }
      done
      ;;
  esac
  return 1
}

# Inline sources into a metadata.json by reading local files for each metadata.sources key.
inline_sources_into_metadata() {
  # $1 = metadata.json path
  local metadata="$1"
  jq -e '.compiler and .language and .sources' "$metadata" >/dev/null 2>&1 || die "Invalid metadata in $metadata"

  local keys
  keys="$(mktemp)"
  jq -r '.sources | keys[]' "$metadata" > "$keys"
  [ -s "$keys" ] || die "metadata.sources is empty in $metadata"

  local missing=0
  # shellcheck disable=SC2162
  while IFS= read key; do
    key="${key%$'\r'}"
    # If content is already embedded, just strip urls for cleanliness
    local hasc
    hasc="$(jq -r --arg k "$key" '(.sources[$k].content // empty) | tostring' "$metadata")"
    if [ -n "$hasc" ] && [ "$hasc" != "null" ]; then
      local tmp; tmp="$(mktemp)"
      jq --arg k "$key" '(.sources[$k] |= (del(.urls)))' "$metadata" > "$tmp" && mv "$tmp" "$metadata"
      continue
    fi
    local path
    if path="$(resolve_local_source "$key")"; then
      local tmp; tmp="$(mktemp)"
      jq --arg k "$key" --rawfile c "$path" '
        (.sources[$k].content = $c) |
        (.sources[$k] |= (del(.urls)))
      ' "$metadata" > "$tmp" && mv "$tmp" "$metadata"
    else
      echo "  ! Missing local source: $key"
      missing=$((missing+1))
    fi
  done < "$keys"
  rm -f "$keys"

  if [ "$missing" -gt 0 ]; then
    echo "  -> WARN: $missing source file(s) could not be inlined"
  else
    echo "  -> OK"
  fi
}

# Build inline metadata bundle for (src, name) into outdir
build_bundle() {
  # $1 = src, $2 = name, $3 = outdir
  local src="$1" name="$2" outdir="$3"
  mkdir -p "$outdir"
  local metadata="$outdir/metadata.json"
  echo "• Building metadata for $src:$name -> $metadata"
  if ! extract_metadata_to "$src" "$name" "$metadata"; then
    die "Could not extract metadata for $name (source '$src'). Ensure you ran: npx hardhat compile"
  fi
  inline_sources_into_metadata "$metadata"
}

# Discover the proxy source path used in your build (avoid guessing)
discover_proxy_source_key() {
  # Walk all dbg.json files; find any whose contractName == NAME_PROXY; read its sourceName/sourcePath.
  local dbg
  dbg="$(find "$ARTIFACTS_DIR" -type f -name "${NAME_PROXY}.dbg.json" 2>/dev/null | head -n1 || true)"
  if [ -n "$dbg" ]; then
    local s
    s="$(jq -r '.sourceName // .sourcePath // empty' "$dbg" 2>/dev/null || true)"
    if [ -n "$s" ]; then
      echo "$s"
      return 0
    fi
  fi
  # Fallback: search build-info contents
  if [ -d "$BUILD_INFO_DIR" ]; then
    # shellcheck disable=SC2044
    for f in $(find "$BUILD_INFO_DIR" -type f -name "*.json"); do
      local s
      s="$(jq -r --arg n "$NAME_PROXY" '
        .output.contracts
        | to_entries[]
        | select(.value[$n])
        | .key
      ' "$f" | awk 'NF{print; exit}')"
      if [ -n "$s" ]; then
        echo "$s"
        return 0
      fi
    done
  fi
  return 1
}

# Compute proxy initializer calldatas (no Foundry needed)
pad64() {
  # lower-case, strip 0x, pad left to 64 nibbles
  # shellcheck disable=SC2001
  local x
  x="$(echo "$1" | sed 's/^0x//' | tr 'A-F' 'a-f')"
  printf "%064s" "$x" | tr ' ' '0'
}

ID_INIT="0x8129fc1c"
REP_INIT=""
VAL_INIT=""
if [ -n "${ID_PROXY:-}" ]; then
  local_id_proxy_padded="$(pad64 "$ID_PROXY")"
  REP_INIT="0xc4d66de8$local_id_proxy_padded"
  VAL_INIT="0xc4d66de8$local_id_proxy_padded"
fi

echo "== Generating inline metadata bundles =="

# Implementations
build_bundle "$SRC_ID"  "$NAME_ID"  "$OUT_BASE/identity-impl"
build_bundle "$SRC_REP" "$NAME_REP" "$OUT_BASE/reputation-impl"
build_bundle "$SRC_VAL" "$NAME_VAL" "$OUT_BASE/validation-impl"

# Proxy
PROXY_SOURCE="$SRC_PROXY_DEFAULT"
if pskey="$(discover_proxy_source_key 2>/dev/null)"; then
  PROXY_SOURCE="$pskey"
  echo "• Proxy source discovered: $PROXY_SOURCE"
else
  echo "• Using proxy source default: $PROXY_SOURCE"
fi
build_bundle "$PROXY_SOURCE" "$NAME_PROXY" "$OUT_BASE/proxy"

# MANIFEST
MANIFEST="$OUT_BASE/MANIFEST.txt"
{
  echo "HashScan Verify Upload Guide"
  echo "============================"
  echo ""
  echo "Go to each contract page on HashScan (e.g., https://hashscan.io/testnet/contract/<address>),"
  echo "click Verify, and upload the matching metadata.json below."
  echo ""
  echo "Implementations:"
  echo "- IdentityRegistryUpgradeable"
  echo "  File: $OUT_BASE/identity-impl/metadata.json"
  [ -n "$ID_IMPL" ] && echo "  Address: $ID_IMPL" || echo "  Address: <set ID_IMPL>"
  echo ""
  echo "- ReputationRegistryUpgradeable"
  echo "  File: $OUT_BASE/reputation-impl/metadata.json"
  [ -n "$REP_IMPL" ] && echo "  Address: $REP_IMPL" || echo "  Address: <set REP_IMPL>"
  echo ""
  echo "- ValidationRegistryUpgradeable"
  echo "  File: $OUT_BASE/validation-impl/metadata.json"
  [ -n "$VAL_IMPL" ] && echo "  Address: $VAL_IMPL" || echo "  Address: <set VAL_IMPL>"
  echo ""
  echo "Proxies (same metadata.json; provide constructor args):"
  echo "- ERC1967Proxy (Identity)"
  echo "  File: $OUT_BASE/proxy/metadata.json"
  [ -n "$ID_PROXY" ] && echo "  Address: $ID_PROXY" || echo "  Address: <set ID_PROXY>"
  echo "  Constructor args (positionally):"
  [ -n "$ID_IMPL" ] && echo "    _logic = $ID_IMPL" || echo "    _logic = <ID_IMPL>"
  echo "    _data  = $ID_INIT"
  echo ""
  echo "- ERC1967Proxy (Reputation)"
  echo "  File: $OUT_BASE/proxy/metadata.json"
  [ -n "$REP_PROXY" ] && echo "  Address: $REP_PROXY" || echo "  Address: <set REP_PROXY>"
  echo "  Constructor args:"
  [ -n "$REP_IMPL" ] && echo "    _logic = $REP_IMPL" || echo "    _logic = <REP_IMPL>"
  [ -n "$REP_INIT" ] && echo "    _data  = $REP_INIT" || echo "    _data  = 0xc4d66de8 + left-padded ID_PROXY"
  echo ""
  echo "- ERC1967Proxy (Validation)"
  echo "  File: $OUT_BASE/proxy/metadata.json"
  [ -n "$VAL_PROXY" ] && echo "  Address: $VAL_PROXY" || echo "  Address: <set VAL_PROXY>"
  echo "  Constructor args:"
  [ -n "$VAL_IMPL" ] && echo "    _logic = $VAL_IMPL" || echo "    _logic = <VAL_IMPL>"
  [ -n "$VAL_INIT" ] && echo "    _data  = $VAL_INIT" || echo "    _data  = 0xc4d66de8 + left-padded ID_PROXY"
  echo ""
  echo "Notes:"
  echo "- Each metadata.json embeds all sources; upload just that single file."
  echo "- If the UI reports a mismatch, ensure your Hardhat compiler settings (solc version, optimizer, viaIR) match what you deployed."
  echo "- If you see 'Missing local source: npm/...', run: npm ci (or npm install) to ensure node_modules is present."
} > "$MANIFEST"

echo ""
echo "Done."
echo "Bundles and manifest are in: $OUT_BASE"
echo "Open $MANIFEST for copy/paste-ready instructions."