# Rust + Foundry Decentralized Polling System Makefile

.PHONY: help install build test clean deploy run

# Default target
help:
	@echo "🚀 Rust + Foundry Decentralized Polling System"
	@echo ""
	@echo "Available commands:"
	@echo "  install     - Install all dependencies"
	@echo "  build       - Build both Rust and Solidity code"
	@echo "  test        - Run all tests"
	@echo "  clean       - Clean build artifacts"
	@echo "  deploy      - Deploy contracts to local network"
	@echo "  anvil       - Start local Anvil blockchain"
	@echo "  run         - Quick commands for common operations"
	@echo "  lint        - Run linting and formatting"

# Installation
install:
	@echo "📦 Installing Rust dependencies..."
	cargo build
	@echo "📦 Installing Foundry dependencies..."
	cd Counter && forge install

# Build
build:
	@echo "🔨 Building Rust application..."
	cargo build --release
	@echo "🔨 Building Solidity contracts..."
	cd Counter && forge build

# Testing
test:
	@echo "🧪 Running Rust tests..."
	cargo test
	@echo "🧪 Running Solidity tests..."
	cd Counter && forge test -vv

test-coverage:
	@echo "📊 Generating test coverage..."
	cd Counter && forge coverage

# Cleaning
clean:
	@echo "🧹 Cleaning Rust artifacts..."
	cargo clean
	@echo "🧹 Cleaning Foundry artifacts..."
	cd Counter && forge clean

# Deployment
anvil:
	@echo "⛏️  Starting Anvil blockchain..."
	anvil --host 0.0.0.0

deploy:
	@echo "🚀 Deploying EnhancedPolls contract..."
	cd Counter && forge script script/EnhancedPolls.s.sol \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

deploy-basic:
	@echo "🚀 Deploying basic DecentralizedPolls contract..."
	cd Counter && forge script script/DecentralizedPolls.s.sol \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

deploy-testnet:
	@echo "🌐 Deploying to testnet..."
	@echo "Make sure to set your PRIVATE_KEY and RPC_URL in .env"
	cd Counter && source ../.env && forge script script/DecentralizedPolls.s.sol \
		--rpc-url $$RPC_URL \
		--private-key $$PRIVATE_KEY \
		--broadcast \
		--verify

# Quick run commands
run-help:
	cargo run -- --help

run-list:
	@echo "📋 Listing all polls..."
	cargo run -- list

run-create-sample:
	@echo "📝 Creating a sample enhanced poll..."
	cargo run -- create \
		-q "What's the best blockchain for DeFi?" \
		-o "Ethereum,Polygon,Solana,Arbitrum" \
		-d 168 \
		--poll-type standard \
		--category technical \
		--description "Community poll about DeFi platforms" \
		--tags "defi,blockchain,community"

run-create-governance:
	@echo "📝 Creating a governance poll..."
	cargo run -- create \
		-q "Should we increase staking rewards?" \
		-o "Yes,No,Abstain" \
		-d 336 \
		--poll-type weighted \
		--category governance \
		--min-participation 10 \
		--description "Important governance decision" \
		--tags "governance,staking,rewards"

run-vote-sample:
	@echo "🗳️  Voting on poll 0, option 0..."
	cargo run -- vote -p 0 -o 0

run-results:
	@echo "📊 Showing results for poll 0..."
	cargo run -- results -p 0

run-list-governance:
	@echo "📋 Listing governance polls..."
	cargo run -- list --category governance

run-list-active:
	@echo "📋 Listing active polls..."
	cargo run -- list --active-only

run-stats:
	@echo "📊 Showing user statistics..."
	cargo run -- my-stats

run-delegation:
	@echo "👥 Showing delegation info..."
	cargo run -- delegation

# Development helpers
lint:
	@echo "🔍 Running Rust formatting and linting..."
	cargo fmt
	cargo clippy -- -D warnings
	@echo "🔍 Running Solidity formatting..."
	cd Counter && forge fmt

watch-tests:
	@echo "👀 Watching for changes and running tests..."
	cargo watch -x test

# Quick setup for new developers
setup: install build
	@echo "✅ Project setup complete!"
	@echo ""
	@echo "Next steps:"
	@echo "1. Copy .env.example to .env and configure"
	@echo "2. Run 'make anvil' in one terminal"
	@echo "3. Run 'make deploy' in another terminal"
	@echo "4. Start using the CLI with 'make run-create-sample'"

# Contract interaction shortcuts
create-poll:
	@read -p "Question: " question; \
	read -p "Options (comma-separated): " options; \
	read -p "Duration in days: " duration; \
	cargo run -- create -q "$$question" -o "$$options" -d "$$duration"

vote:
	@read -p "Poll ID: " poll_id; \
	read -p "Option index: " option; \
	cargo run -- vote -p "$$poll_id" -o "$$option"

# Utility commands
check-env:
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found. Copy .env.example to .env"; \
		exit 1; \
	fi
	@echo "✅ Environment configuration found"

logs:
	@echo "📋 Recent transaction logs..."
	cd Counter && forge logs

# Development workflow
dev: check-env build
	@echo "🚀 Starting development environment..."
	@echo "Run 'make anvil' in another terminal first!"
	make deploy
	@echo "Ready for development! Try 'make run-create-sample'" 