# ♻️ Recycla - Recycling Incentive Protocol

A decentralized platform built on Stacks that incentivizes recycling by rewarding users with tokens for reporting waste locations and confirming recycling activities.

## 🌟 Features

- 📍 **Waste Reporting**: Users can report waste locations with GPS coordinates
- ✅ **Community Verification**: Reports are verified by community members
- 🏆 **Recycling Rewards**: Users earn tokens for recycling reported waste
- 👤 **Reputation System**: Build reputation through consistent participation
- 💰 **Token Economy**: Earn and transfer Recycla tokens
- 📊 **Activity Tracking**: Track personal and global recycling statistics

## 🚀 Getting Started

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity smart contracts

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Initialize the contract:

```bash
clarinet console
```

```bash
(contract-call? .Recycla initialize-contract u1000000)
```

## 📖 Usage

### 🗑️ Report Waste

Report waste at a specific location:

```clarity
(contract-call? .Recycla report-waste 40748817 -73985428 "plastic" u50)
```

Parameters:
- `lat`: Latitude (multiplied by 1,000,000)
- `lng`: Longitude (multiplied by 1,000,000)  
- `waste-type`: Type of waste (max 50 characters)
- `amount`: Estimated amount in kg

### ✅ Verify Reports

Help verify waste reports from other users:

```clarity
(contract-call? .Recycla verify-report u1)
```

- Earn 50 tokens per verification
- Cannot verify your own reports
- Minimum 3 verifications needed for report approval

### ♻️ Confirm Recycling

Confirm that you've recycled reported waste:

```clarity
(contract-call? .Recycla confirm-recycling u1)
```

- Only verified reports can be recycled
- Earn base reward + amount-based bonus
- Original reporter also receives reward

### 💎 Claim Rewards

Claim rewards for verified reports:

```clarity
(contract-call? .Recycla claim-report-reward u1)
```

### 💸 Transfer Tokens

Transfer tokens to other users:

```clarity
(contract-call? .Recycla transfer-tokens 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7 u100)
```

## 📊 Read-Only Functions

### Get Report Details
```clarity
(contract-call? .Recycla get-report u1)
```

### Check User Profile
```clarity
(contract-call? .Recycla get-user-profile 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Check Token Balance
```clarity
(contract-call? .Recycla get-user-balance 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Get Contract Statistics
```clarity
(contract-call? .Recycla get-contract-stats)
```

## 🎯 Reward System

| Action | Base Reward | Bonus |
|--------|-------------|-------|
| Report Verification | 50 tokens | - |
| Waste Reporting | 100 tokens | +2 per kg |
| Recycling Confirmation | 200 tokens | +5 per kg |

### 🏅 Reputation Multipliers

- **Beginner** (0-500 points): 100% rewards
- **Intermediate** (500-1000 points): 125% rewards  
- **Expert** (1000+ points): 150% rewards

Reputation is earned through:
