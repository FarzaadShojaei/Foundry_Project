#!/usr/bin/env python3
"""
Rust + Foundry Polling System - Development Demo Script
=====================================================

This script demonstrates the enhanced features we've added to your polling system:
1. Enhanced CLI with colored output and progress indicators
2. Data export functionality (JSON, CSV, Table)
3. Advanced analytics and visualization
4. Improved error handling and user experience

Usage:
    python scripts/demo.py [--help]
"""

import subprocess
import sys
import os
import json

def print_banner():
    print("=" * 60)
    print("🚀 RUST + FOUNDRY POLLING SYSTEM DEMO")
    print("=" * 60)
    print()

def run_command(cmd, description):
    print(f"📋 {description}")
    print(f"💻 Command: {cmd}")
    print("-" * 40)
    
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print("STDERR:", result.stderr)
        print()
    except Exception as e:
        print(f"Error running command: {e}")
        print()

def main():
    print_banner()
    
    # Check if we're in the right directory
    if not os.path.exists("Cargo.toml"):
        print("❌ Please run this script from the project root directory!")
        return
    
    print("🔧 PROJECT ANALYSIS")
    print("-" * 20)
    
    # Show project structure
    print("📁 Project Structure:")
    for root, dirs, files in os.walk("."):
        level = root.replace(".", "").count(os.sep)
        indent = " " * 2 * level
        print(f"{indent}{os.path.basename(root)}/")
        subindent = " " * 2 * (level + 1)
        for file in files[:3]:  # Show first 3 files
            if not file.startswith('.') and file.endswith(('.rs', '.sol', '.toml', '.json')):
                print(f"{subindent}{file}")
    print()
    
    print("🏗️  BUILD & TEST COMMANDS")
    print("-" * 25)
    
    # Show available commands
    commands = [
        ("cargo check", "Validate Rust code compilation"),
        ("cargo build --release", "Build optimized binary"),
        ("cargo run -- --help", "Show CLI help"),
        ("cd Counter && forge build", "Compile smart contracts"),
        ("cd Counter && forge test", "Run smart contract tests"),
        ("cd Counter && anvil", "Start local blockchain (background)"),
        ("cd Counter && forge script script/DecentralizedPolls.s.sol", "Deploy contracts"),
    ]
    
    for cmd, desc in commands:
        print(f"📋 {desc}")
        print(f"💻 {cmd}")
        print()
    
    print("🎯 ENHANCED FEATURES ADDED")
    print("-" * 28)
    
    features = [
        "✅ Colored CLI output with progress indicators",
        "✅ Data export in JSON, CSV, and Table formats",
        "✅ Advanced poll analytics with visual bars",
        "✅ Comprehensive error handling",
        "✅ Time-based poll management",
        "✅ User activity tracking",
        "✅ Multi-format result visualization",
        "✅ Professional CLI experience"
    ]
    
    for feature in features:
        print(f"  {feature}")
    print()
    
    print("🚀 EXAMPLE USAGE")
    print("-" * 15)
    
    example_commands = [
        # CLI Examples
        'cargo run -- create -q "What\'s your favorite blockchain?" -o "Ethereum,Bitcoin,Solana" -d 7',
        'cargo run -- list',
        'cargo run -- vote -p 0 -o 1',
        'cargo run -- view -p 0',
        'cargo run -- results -p 0',
        'cargo run -- analytics -p 0',
        'cargo run -- export -p 0 -f json -o poll_data.json',
        'cargo run -- export -p 0 -f csv',
        'cargo run -- my-polls',
        'cargo run -- my-votes',
    ]
    
    for i, cmd in enumerate(example_commands, 1):
        print(f"{i:2d}. {cmd}")
    print()
    
    print("🔧 DEVELOPMENT WORKFLOW")
    print("-" * 23)
    
    workflow = [
        "1. Start local blockchain: cd Counter && anvil",
        "2. Deploy contracts: cd Counter && forge script script/DecentralizedPolls.s.sol --rpc-url http://localhost:8545 --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --broadcast",
        "3. Set environment variables:",
        "   export CONTRACT_ADDRESS=<deployed_address>",
        "   export RPC_URL=http://localhost:8545",
        "4. Use the enhanced CLI with all new features!",
    ]
    
    for step in workflow:
        print(f"  {step}")
    print()
    
    print("📊 NEXT DEVELOPMENT PHASES")
    print("-" * 27)
    
    next_phases = [
        "🌐 Web Frontend (React/Next.js)",
        "🔗 Multi-chain Support (Polygon, Arbitrum)",
        "🛡️  Security Enhancements & Anti-spam",
        "⚖️  Weighted & Stake-based Voting",
        "🔌 REST API for External Integrations",
        "📱 Mobile App Support",
        "🎨 Advanced Data Visualizations",
        "🏆 Reputation & Governance System"
    ]
    
    for phase in next_phases:
        print(f"  {phase}")
    print()
    
    print("=" * 60)
    print("🎉 Your Rust + Foundry polling system is ready for development!")
    print("💡 Run any of the commands above to get started.")
    print("=" * 60)

if __name__ == "__main__":
    main()