# ERC-8004: Trustless Agents

Implementation of the ERC-8004 protocol for agent discovery and trust through reputation and validation.

## About

This project implements **ERC-8004**, a protocol that enables discovering, choosing, and interacting with agents across organizational boundaries without pre-existing trust. It provides three core registries:

- **Identity Registry**: A minimal on-chain handle based on ERC-721 with URIStorage extension that gives every agent a portable, censorship-resistant identifier
- **Reputation Registry**: A standard interface for posting and fetching feedback signals, enabling composable reputation systems
- **Validation Registry**: Generic hooks for requesting and recording independent validator checks (e.g., stakers re-running jobs, zkML verifiers, TEE oracles)

## Project Structure

```
contracts/
├── IdentityRegistry.sol     - ERC-721 based agent registration
├── ReputationRegistry.sol   - Feedback and reputation tracking
└── ValidationRegistry.sol   - Validation request/response system

test/
└── ERC8004.ts              - Comprehensive test suite

ERC8004SPEC.md              - Full protocol specification
```

## Key Features

### Identity Registry
- ERC-721 NFT-based agent registration with auto-incrementing agent IDs
- Token URI points to agent registration file (IPFS, HTTPS, etc.)
- On-chain metadata storage for key-value pairs (e.g., agentWallet, agentName)
- Support for metadata during registration

### Reputation Registry
- Clients can give feedback (0-100 score) with optional tags and off-chain file references
- Pre-authorization via cryptographic signatures (`feedbackAuth`)
- Support for feedback revocation and responses
- On-chain aggregation (count, average score) with filtering by client addresses and tags
- Multiple feedback entries per client-agent pair

### Validation Registry
- Agents request validation from specific validators
- Validators respond with 0-100 scores and optional tags
- Support for progressive validation states
- Track all validations per agent and per validator
- On-chain aggregation with filtering

## Installation

```shell
npm install
```

## Running Tests

Run all tests:
```shell
npm test
```

Or using Hardhat directly:
```shell
npx hardhat test
```

The test suite includes comprehensive coverage of:
- Agent registration and metadata management
- Feedback submission, revocation, and responses
- FeedbackAuth signature verification (EIP-191)
- Validation requests and responses
- Permission controls and access restrictions
- Summary calculations with filtering
- Edge cases and error conditions

## Development

This project uses:
- **Hardhat 3** with native Node.js test runner (`node:test`)
- **Viem** for Ethereum interactions
- **TypeScript** for type safety
- **OpenZeppelin Contracts** for ERC-721 implementation

## Protocol Overview

### Agent Registration
Each agent is uniquely identified by:
- `namespace`: eip155 (for EVM chains)
- `chainId`: The blockchain network identifier
- `identityRegistry`: The registry contract address
- `agentId`: The ERC-721 token ID

### Trust Models
ERC-8004 supports three pluggable trust models:
1. **Reputation**: Client feedback and scoring
2. **Validation**: Stake-secured re-execution, zkML proofs, or TEE oracles
3. **TEE Attestation**: Trusted Execution Environment verification

### Security Considerations
- Pre-authorization mitigates unauthorized feedback but doesn't prevent Sybil attacks
- On-chain pointers and hashes ensure immutable audit trails
- Validator incentives and slashing managed by specific validation protocols
- Reputation aggregation expected to evolve with off-chain services

## Resources

- [ERC-8004 Full Specification](./ERC8004SPEC.md)
- [Hardhat Documentation](https://hardhat.org/docs)
- [EIP-721: Non-Fungible Token Standard](https://eips.ethereum.org/EIPS/eip-721)

## License

CC0 - Public Domain
