// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DecentralizedPolls} from "../src/DecentralizedPolls.sol";

contract DecentralizedPollsScript is Script {
    DecentralizedPolls public polls;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy the contract
        polls = new DecentralizedPolls();

        console.log("DecentralizedPolls deployed at:", address(polls));

        // Create a sample poll for testing
        string[] memory options = new string[](3);
        options[0] = "Ethereum";
        options[1] = "Bitcoin";
        options[2] = "Solana";

        uint256 pollId = polls.createPoll(
            "Which blockchain do you prefer for DeFi?",
            options,
            30 // 30 days
        );

        console.log("Sample poll created with ID:", pollId);

        vm.stopBroadcast();
    }

    // Helper function to create multiple test polls
    function createTestPolls() public {
        vm.startBroadcast();

        // Poll 1: Programming Languages
        string[] memory progLangs = new string[](4);
        progLangs[0] = "Rust";
        progLangs[1] = "JavaScript";
        progLangs[2] = "Python";
        progLangs[3] = "Go";

        polls.createPoll("Best programming language for web3?", progLangs, 14);

        // Poll 2: DeFi Protocols
        string[] memory defiProtos = new string[](3);
        defiProtos[0] = "Uniswap";
        defiProtos[1] = "Aave";
        defiProtos[2] = "Compound";

        polls.createPoll("Most innovative DeFi protocol?", defiProtos, 21);

        // Poll 3: NFT Marketplaces
        string[] memory nftMarkets = new string[](3);
        nftMarkets[0] = "OpenSea";
        nftMarkets[1] = "Blur";
        nftMarkets[2] = "LooksRare";

        polls.createPoll("Best NFT marketplace?", nftMarkets, 7);

        console.log("Test polls created successfully");

        vm.stopBroadcast();
    }
}