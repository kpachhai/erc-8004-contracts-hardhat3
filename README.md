# ERC-8004: Trustless Agents

Implementation of the ERC-8004 protocol for agent discovery and trust through reputation and validation.

## Installation

```shell
npm install
```

## Deployment and Verification

### Deployment of upgradeable contracts

```shell
npm run deploy:upgradeable:hederaTestnet
```

### Verify (single command)

After a successful run, copy the printed addresses:

```text
IdentityRegistry Proxy:            0x...
ReputationRegistry Proxy:          0x...
ValidationRegistry Proxy:          0x...

IdentityRegistry Implementation:   0x...
ReputationRegistry Implementation: 0x...
ValidationRegistry Implementation: 0x...
```

Optionally export them for verification:

```bash
export ID_PROXY=0x...
export REP_PROXY=0x...
export VAL_PROXY=0x...

export ID_IMPL=0x...
export REP_IMPL=0x...
export VAL_IMPL=0x...
```

Run the helper script to verify all 3 implementations and 3 proxies on Hedera via hashscan-verify (Hardhat v3 plugin):

```bash
# Make sure the six env vars are set (see above)
npm run verify:upgradeable:hederaTestnet
```

### How verification works (under the hood)

The verify script calls Hardhat’s hashscan-verify task with explicit contracts and positional constructor args for proxies.

1. Implementations

```bash
# Identity
npx hardhat hashscan-verify "$ID_IMPL" \
  --contract "contracts/IdentityRegistryUpgradeable.sol:IdentityRegistryUpgradeable" \
  --network hederaTestnet

# Reputation
npx hardhat hashscan-verify "$REP_IMPL" \
  --contract "contracts/ReputationRegistryUpgradeable.sol:ReputationRegistryUpgradeable" \
  --network hederaTestnet

# Validation
npx hardhat hashscan-verify "$VAL_IMPL" \
  --contract "contracts/ValidationRegistryUpgradeable.sol:ValidationRegistryUpgradeable" \
  --network hederaTestnet
```

2. Proxies (constructor is (address \_logic, bytes \_data), passed positionally)

```bash
# Initializer calldatas
IDENTITY_INIT=0x8129fc1c                                # initialize()
# initialize(address) selector = 0xc4d66de8
pad64() { x="${1#0x}"; printf "%064s" "$x" | tr ' ' '0'; }
ID_PROXY_P=$(pad64 "$ID_PROXY")
REPUTATION_INIT="0xc4d66de8${ID_PROXY_P}"
VALIDATION_INIT="0xc4d66de8${ID_PROXY_P}"

# Identity proxy
npx hardhat hashscan-verify "$ID_PROXY" \
  --contract "contracts/ERC1967Proxy.sol:ERC1967Proxy" \
  "$ID_IMPL" "$IDENTITY_INIT" \
  --network hederaTestnet

# Reputation proxy
npx hardhat hashscan-verify "$REP_PROXY" \
  --contract "contracts/ERC1967Proxy.sol:ERC1967Proxy" \
  "$REP_IMPL" "$REPUTATION_INIT" \
  --network hederaTestnet

# Validation proxy
npx hardhat hashscan-verify "$VAL_PROXY" \
  --contract "contracts/ERC1967Proxy.sol:ERC1967Proxy" \
  "$VAL_IMPL" "$VALIDATION_INIT" \
  --network hederaTestnet
```

Notes:

- The task will prompt once for your Hardhat keystore password.
- A perfect match is expected for implementations. Proxies may show perfect or partial matches depending on creation-bytecode checks.

## Manual verification on HashScan (upload metadata.json)

Prefer the UI route? Generate self-contained metadata.json files (with all sources embedded) and upload one file per address on HashScan.

1. Export addresses from your deployment (or copy them from the console output):

```bash
export ID_IMPL=0x...
export REP_IMPL=0x...
export VAL_IMPL=0x...

export ID_PROXY=0x...
export REP_PROXY=0x...
export VAL_PROXY=0x...
```

2. Generate inline metadata bundles:

```bash
./make_sourcify_inline_metadata.sh
```

This produces:

```
verify-bundles/
  identity-impl/metadata.json
  reputation-impl/metadata.json
  validation-impl/metadata.json
  proxy/metadata.json
  MANIFEST.txt
```

3. On HashScan, go to each contract’s page and click “Verify”, then upload the corresponding metadata.json:

- Example page: https://hashscan.io/testnet/contract/0x7c559a9f0d6045a1916f8d957337661de1a16732

Use this mapping:

- Identity implementation address → upload `verify-bundles/identity-impl/metadata.json`
- Reputation implementation address → upload `verify-bundles/reputation-impl/metadata.json`
- Validation implementation address → upload `verify-bundles/validation-impl/metadata.json`
- For each ERC1967 proxy (Identity/Reputation/Validation) → upload the same `verify-bundles/proxy/metadata.json`

Notes:

- Hardhat v3 records dependency sources as npm/@package@version/...; ensure node_modules is installed (npm ci) so the script can inline them.
- If the UI reports a mismatch, confirm your compile settings match deployment (solc, optimizer, viaIR). Re-run: npx hardhat clean && npx hardhat compile, regenerate bundles, and retry.

## License

MIT
