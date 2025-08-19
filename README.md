# RWAx: Real World Asset Tokenization Smart Contract

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

RWAx is a Clarity smart contract for tokenizing real-world assets (RWA) on the Stacks blockchain. It implements a comprehensive solution for compliant asset tokenization with features including KYC controls, dividend distribution, and NAV-based redemptions.

## Key Features

### Compliance & Security
- 🔒 Role-based access control (Owner, Operators, Auditors)
- ✅ KYC whitelist system
- ⛔ Blacklist functionality
- 🔐 Token lockup periods
- ⏸️ Pausable transfers

### Token Economics
- 📈 SIP-010 compliant fungible token
- 💰 Maximum supply: 1B tokens (6 decimals)
- 💱 NAV-based redemptions
- 📊 Dynamic price updates
- 💸 Management fee system

### Dividend System
- 💵 STX dividend deposits
- 📑 Per-share dividend tracking
- 🔄 Reinvestment options
- 📈 Automated distribution calculations

## Technical Implementation

### Core Functions

```clarity
;; Token Management
(define-public (mint (to principal) (amount uint)))
(define-public (burn (from principal) (amount uint)))
(define-public (transfer (amount uint) (sender principal) (recipient principal)))

;; Dividend Operations
(define-public (deposit-dividends (amount uint)))
(define-public (claim-dividends))
(define-public (reinvest-dividends))

;; NAV & Redemption
(define-public (set-nav (price uint)))
(define-public (redeem (amount uint)))
```

### Administrative Functions

```clarity
;; Compliance Controls
(define-public (kyc-set (who principal) (on bool)))
(define-public (blacklist-set (who principal) (on bool)))
(define-public (set-lockup (who principal) (unlock-height uint)))

;; Role Management
(define-public (set-operator (who principal) (on bool)))
(define-public (set-auditor (who principal) (on bool)))
```

## Getting Started

### Prerequisites
- Clarity CLI
- Stacks blockchain node (testnet/mainnet)
- Clarity VS Code extension (recommended)

### Deployment

1. Clone the repository
```bash
git clone https://github.com/yourusername/rwax-contract
```

2. Test the contract
```bash
clarity-cli test /path/to/AssetLinker.clar
```

3. Deploy using Clarinet or Stacks CLI
```bash
clarinet deploy
```

## Usage Examples

### Minting Tokens
```clarity
(contract-call? .rwax mint tx-sender u1000000)
```

### Depositing Dividends
```clarity
(contract-call? .rwax deposit-dividends u5000000)
```

### Checking Dividend Balance
```clarity
(contract-call? .rwax pending-dividends tx-sender)
```

## Security Considerations

- Role-based access control for all administrative functions
- KYC requirements for transfers
- Blacklist capability for regulatory compliance
- Lock-up periods for vesting schedules
- Pausable transfers for emergency situations




## Acknowledgments

- Stacks Foundation
- Clarity Lang Documentation
- SIP-010 Standard


**Note:** This contract is provided as-is. Always conduct thorough testing and security audits before deploying to production.

Similar code found with 3 license types
