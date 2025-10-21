#!/usr/bin/env bash
set -euo pipefail

# Defaults (override via env)
: "${NETWORK:=hederaTestnet}"       # Your Hardhat network name
: "${SOURCE_DIR:=contracts}"        # Your sources live in contracts here
: "${SHOW_ERRORS:=1}"               # 1 = show task errors if verification fails

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need npx
need mktemp

# Required addresses from deployment output
vars=(ID_IMPL REP_IMPL VAL_IMPL ID_PROXY REP_PROXY VAL_PROXY)
for v in "${vars[@]}"; do
  if [[ -z "${!v:-}" ]]; then
    echo "Env var $v is required. Export all of: ${vars[*]}" >&2
    exit 1
  fi
done

# Colors
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'
ok()    { printf "${GREEN}✔ %s${NC}\n" "$*"; }
info()  { printf "${YELLOW}ℹ %s${NC}\n" "$*"; }
fail()  { printf "${RED}✘ %s${NC}\n" "$*"; }

printf "== Verifying on network: %s\n" "$NETWORK"
printf "Sources: %s\n\n" "$SOURCE_DIR"
echo "Addresses:"
printf "  ID_IMPL=%s\n  REP_IMPL=%s\n  VAL_IMPL=%s\n" "$ID_IMPL" "$REP_IMPL" "$VAL_IMPL"
printf "  ID_PROXY=%s\n  REP_PROXY=%s\n  VAL_PROXY=%s\n" "$ID_PROXY" "$REP_PROXY" "$VAL_PROXY"
echo ""

# Prompt ONCE for keystore password (hidden, not echoed)
KEYSTORE_PASS="${KEYSTORE_PASS:-}"
if [[ -z "${KEYSTORE_PASS}" ]]; then
  read -s -p "[hardhat-keystore] Password (input hidden): " KEYSTORE_PASS
  echo
fi

# Helper: left-pad hex to 64 nybbles (32 bytes) without 0x
pad64() {
  local x="${1#0x}"
  printf "%064s" "$x" | tr ' ' '0'
}

# Initializer calldata for proxies
IDENTITY_INIT="0x8129fc1c"                    # initialize()
SEL_INIT_ADDR="0xc4d66de8"                    # initialize(address)
ID_PROXY_P=$(pad64 "$ID_PROXY")
REPUTATION_INIT="${SEL_INIT_ADDR}${ID_PROXY_P}"
VALIDATION_INIT="${SEL_INIT_ADDR}${ID_PROXY_P}"

# Print a clear section banner
section() {
  local title="$1"
  printf "\n==================== %s ====================\n" "$title"
}

# Run one verification with clear start/end and filtered output
# Positional constructor args come before --network.
run_verify() {
  local label="$1" addr="$2" fqcn="$3"
  shift 3

  section "Verify: $label @ $addr"

  # Build and display the EXACT command that will run (without revealing the password)
  local cmd_str
  cmd_str="HARDHAT_NETWORK=\"$NETWORK\" npx hardhat hashscan-verify $addr --contract \"$fqcn\""
  for arg in "$@"; do
    cmd_str+=" \"$arg\""
  done
  cmd_str+=" --network \"$NETWORK\""
  echo "> $cmd_str"

  local tmp raw filtered code
  tmp="$(mktemp)"
  raw="$(mktemp)"

  # Execute: feed password via stdin; capture full output to $raw; record exit code
  set +e
  { printf "%s\n" "$KEYSTORE_PASS" | HARDHAT_NETWORK="$NETWORK" npx hardhat hashscan-verify "$addr" --contract "$fqcn" "$@" --network "$NETWORK"; } >"$raw" 2>&1
  code=$?
  set -e

  # Filter out the keystore prompt line to reduce noise
  filtered="$(mktemp)"
  sed '/^\[hardhat-keystore] Enter the password:/d' "$raw" > "$filtered"

  # Show filtered output to the user and keep a copy for parsing
  cat "$filtered" | tee "$tmp" >/dev/null

  # Result summary
  if grep -qi "already verified" "$tmp"; then
    ok "Already verified: $label @ $addr"
  elif [[ $code -eq 0 ]]; then
    if grep -qi "perfect match" "$tmp"; then
      ok "Verified (perfect match): $label @ $addr"
    elif grep -qi "partial match" "$tmp"; then
      ok "Verified (partial match): $label @ $addr"
    else
      ok "Verified: $label @ $addr"
    fi
  else
    fail "Failed: $label @ $addr"
    if [[ "$SHOW_ERRORS" -eq 1 ]]; then
      echo "---- verifier output ----"
      cat "$tmp"
      echo "-------------------------"
    fi
    rm -f "$tmp" "$raw" "$filtered"
    return 1
  fi

  rm -f "$tmp" "$raw" "$filtered"
}

section "Implementations"
# No constructor args for implementations
run_verify "IdentityRegistryUpgradeable"   "$ID_IMPL"  "$SOURCE_DIR/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable"
run_verify "ReputationRegistryUpgradeable" "$REP_IMPL" "$SOURCE_DIR/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable"
run_verify "ValidationRegistryUpgradeable" "$VAL_IMPL" "$SOURCE_DIR/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable"

section "Proxies (ERC1967Proxy)"
# Positional constructor args: (address _logic, bytes _data)
run_verify "ERC1967Proxy (Identity)"   "$ID_PROXY"  "$SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy"  "$ID_IMPL"  "$IDENTITY_INIT"
run_verify "ERC1967Proxy (Reputation)" "$REP_PROXY" "$SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy"  "$REP_IMPL" "$REPUTATION_INIT"
run_verify "ERC1967Proxy (Validation)" "$VAL_PROXY" "$SOURCE_DIR/ERC1967Proxy.sol:ERC1967Proxy"  "$VAL_IMPL" "$VALIDATION_INIT"

echo ""
ok "All verifications complete."