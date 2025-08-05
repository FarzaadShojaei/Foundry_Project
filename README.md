# 🚀 Rust + Foundry Decentralized Polling System

A comprehensive blockchain-based polling platform built with **Rust** and **Foundry**, featuring advanced CLI tools, smart contracts, and data analytics.

## ✨ Features

### 🎯 Core Functionality
- **Decentralized Polls**: Create time-limited polls with multiple options
- **Secure Voting**: One vote per user with blockchain verification
- **Poll Management**: Creator controls and automatic expiration
- **User Tracking**: Track created polls and voting history

### 🎨 Enhanced CLI Experience
- **Colored Output**: Beautiful, intuitive interface with emojis and colors
- **Progress Indicators**: Real-time feedback for blockchain transactions
- **Multiple Export Formats**: JSON, CSV, and formatted tables
- **Advanced Analytics**: Detailed poll statistics with visual bars
- **Professional UX**: Spinner animations and formatted results

### 🔧 Technical Stack
- **Backend**: Rust with ethers-rs for blockchain interaction
- **Smart Contracts**: Solidity with Foundry framework
- **Testing**: Comprehensive test suite with fuzz testing
- **CLI**: clap for argument parsing, colored output, progress bars

## 🏗️ Project Structure

```
Rust_Foundry/
├── src/
│   └── main.rs                 # Enhanced CLI with analytics & export
├── Counter/
│   ├── src/
│   │   ├── DecentralizedPolls.sol  # Main polling contract
│   │   └── Counter.sol             # Example contract
│   ├── test/                   # Comprehensive test suite
│   ├── script/                 # Deployment scripts
│   └── foundry.toml           # Foundry configuration
├── Cargo.toml                 # Rust dependencies
└── scripts/
    └── demo.py               # Development demo script
```

## 🚀 Quick Start

### Prerequisites
- [Rust](https://rustup.rs/) (latest stable)
- [Foundry](https://getfoundry.sh/)
- Git

### 1. Setup
```bash
# Clone and enter the project
git clone <your-repo>
cd Rust_Foundry

# Install Rust dependencies
cargo build --release

# Install Foundry dependencies
cd Counter
forge install
forge build
```

### 2. Start Local Blockchain
```bash
cd Counter
anvil
```

### 3. Deploy Contracts
```bash
# In a new terminal
cd Counter
forge script script/DecentralizedPolls.s.sol \
  --rpc-url http://localhost:8545 \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
```

### 4. Set Environment Variables
```bash
export CONTRACT_ADDRESS=<deployed_contract_address>
export RPC_URL=http://localhost:8545
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```

### 5. Use the CLI
```bash
# Create a poll
cargo run -- create \
  -q "What's your favorite blockchain?" \
  -o "Ethereum,Bitcoin,Solana,Polygon" \
  -d 7

# List all polls
cargo run -- list

# Vote on a poll
cargo run -- vote -p 0 -o 1

# View detailed poll results
cargo run -- view -p 0

# Generate analytics
cargo run -- analytics -p 0

# Export data
cargo run -- export -p 0 -f json -o poll_data.json
```

## 📊 Enhanced CLI Commands

### Core Commands
- `create` - Create a new poll with question, options, and duration
- `vote` - Cast a vote on a specific poll
- `view` - View detailed poll information with live results
- `list` - List all polls with status indicators
- `results` - Display poll results with visual bars
- `close` - Close a poll (creator only)

### New Enhanced Features
- `analytics` - Generate comprehensive poll analytics
- `export` - Export poll data in JSON, CSV, or table format
- `my-polls` - View polls you've created
- `my-votes` - View polls you've voted on

### Export Formats
```bash
# JSON export
cargo run -- export -p 0 -f json -o data.json

# CSV export for spreadsheets
cargo run -- export -p 0 -f csv -o data.csv

# Formatted table for terminal
cargo run -- export -p 0 -f table
```

## 🧪 Testing

### Smart Contract Tests
```bash
cd Counter
forge test -vv
```

### Fuzz Testing
```bash
cd Counter
forge test --fuzz-runs 1000
```

### Test Coverage
```bash
cd Counter
forge coverage
```

## 🔧 Development

### Build
```bash
# Debug build
cargo build

# Release build
cargo build --release

# Smart contracts
cd Counter && forge build
```

### Code Quality
```bash
# Check Rust code
cargo check
cargo clippy

# Format code
cargo fmt
cd Counter && forge fmt
```

## 📈 Advanced Features

### Analytics Dashboard
- **Poll Performance**: Vote counts, participation rates
- **Time Analysis**: Time remaining, creation dates
- **Result Visualization**: ASCII bar charts, percentages
- **System Overview**: Total polls, active/closed status

### Data Export
- **JSON**: Structured data for APIs and databases
- **CSV**: Spreadsheet-compatible format
- **Table**: Formatted terminal output

### User Experience
- **Progress Spinners**: Real-time transaction feedback
- **Colored Output**: Intuitive visual hierarchy
- **Error Handling**: Clear, actionable error messages
- **Smart Formatting**: Timestamps, percentages, visual bars

## 🛣️ Roadmap

### Phase 1: Core Enhancement ✅
- [x] Enhanced CLI with colors and progress indicators
- [x] Data export functionality (JSON, CSV, Table)
- [x] Advanced analytics and visualization
- [x] Improved error handling

### Phase 2: Web Interface 🔄
- [ ] React/Next.js frontend
- [ ] Real-time poll updates
- [ ] Mobile-responsive design
- [ ] Web3 wallet integration

### Phase 3: Advanced Features 📋
- [ ] Multi-chain support (Polygon, Arbitrum, Base)
- [ ] Weighted voting mechanisms
- [ ] Stake-based voting
- [ ] Poll verification system

### Phase 4: Enterprise Features 🎯
- [ ] REST API for integrations
- [ ] Reputation system
- [ ] Advanced governance features
- [ ] Analytics dashboard

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature-name`
3. Make your changes and test thoroughly
4. Submit a pull request with a clear description

## 📄 License

This project is open source. See the LICENSE file for details.

## 🙏 Acknowledgments

- **Foundry** - Ethereum development framework
- **ethers-rs** - Ethereum library for Rust
- **clap** - Command line argument parsing
- **colored** - Terminal color support

---

**Built with ❤️ using Rust and Foundry**

Ready to revolutionize decentralized polling! 🗳️✨