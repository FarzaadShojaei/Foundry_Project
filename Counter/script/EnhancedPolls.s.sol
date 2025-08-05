// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {EnhancedPolls} from "../src/EnhancedPolls.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract EnhancedPollsScript is Script {
    EnhancedPolls public enhancedPolls;
    GovernanceToken public governanceToken;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // Deploy governance token first
        console.log("Deploying GovernanceToken...");
        governanceToken = new GovernanceToken();
        console.log("GovernanceToken deployed to:", address(governanceToken));

        // Deploy enhanced polls contract
        console.log("Deploying EnhancedPolls...");
        enhancedPolls = new EnhancedPolls(address(governanceToken));
        console.log("EnhancedPolls deployed to:", address(enhancedPolls));

        // Create some test polls with different features
        createTestPolls();

        // Setup delegation examples
        setupDelegationExamples();

        // Demonstrate analytics
        demonstrateAnalytics();

        vm.stopBroadcast();

        // Print deployment summary
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("GovernanceToken:", address(governanceToken));
        console.log("EnhancedPolls:", address(enhancedPolls));
        console.log("========================");
    }

    function createTestPolls() internal {
        console.log("\nCreating test polls...");

        // Test poll 1: Standard poll
        string[] memory options1 = new string[](3);
        options1[0] = "Ethereum";
        options1[1] = "Polygon";
        options1[2] = "Arbitrum";

        string[] memory tags1 = new string[](2);
        tags1[0] = "blockchain";
        tags1[1] = "defi";

        uint256 pollId1 = enhancedPolls.createPoll(
            "What's the best Layer 2 solution?",
            options1,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.TECHNICAL,
            5, // min participation
            address(0), // no token required
            0,
            "Comparing different Layer 2 scaling solutions for Ethereum",
            tags1
        );
        console.log("Created standard poll with ID:", pollId1);

        // Test poll 2: Weighted voting with governance token
        string[] memory options2 = new string[](4);
        options2[0] = "Increase rewards";
        options2[1] = "Decrease rewards";
        options2[2] = "Keep current";
        options2[3] = "Dynamic adjustment";

        string[] memory tags2 = new string[](2);
        tags2[0] = "governance";
        tags2[1] = "rewards";

        uint256 pollId2 = enhancedPolls.createPoll(
            "How should we adjust staking rewards?",
            options2,
            14 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            10, // min participation
            address(governanceToken), // requires governance token
            1000 * 1e18, // minimum 1000 tokens
            "Governance proposal to adjust the staking reward mechanism",
            tags2
        );
        console.log("Created weighted governance poll with ID:", pollId2);

        // Test poll 3: Quadratic voting
        string[] memory options3 = new string[](3);
        options3[0] = "Conservative approach";
        options3[1] = "Moderate approach";
        options3[2] = "Aggressive approach";

        string[] memory tags3 = new string[](2);
        tags3[0] = "strategy";
        tags3[1] = "finance";

        uint256 pollId3 = enhancedPolls.createPoll(
            "What investment strategy should the DAO pursue?",
            options3,
            30 days,
            EnhancedPolls.PollType.QUADRATIC,
            EnhancedPolls.PollCategory.FINANCE,
            20, // min participation
            address(governanceToken), // requires governance token
            500 * 1e18, // minimum 500 tokens
            "Strategic decision for the DAO's investment portfolio allocation",
            tags3
        );
        console.log("Created quadratic voting poll with ID:", pollId3);

        // Test poll 4: Community poll
        string[] memory options4 = new string[](5);
        options4[0] = "Weekly";
        options4[1] = "Bi-weekly";
        options4[2] = "Monthly";
        options4[3] = "Quarterly";
        options4[4] = "As needed";

        string[] memory tags4 = new string[](2);
        tags4[0] = "community";
        tags4[1] = "events";

        uint256 pollId4 = enhancedPolls.createPoll(
            "How often should we hold community events?",
            options4,
            21 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.COMMUNITY,
            3, // min participation
            address(0), // no token required
            0,
            "Planning the frequency of community engagement events",
            tags4
        );
        console.log("Created community poll with ID:", pollId4);

        // Test poll 5: Created from template
        string[] memory options5 = new string[](2);
        options5[0] = "Approve";
        options5[1] = "Reject";

        string[] memory tags5 = new string[](1);
        tags5[0] = "custom";

        uint256 pollId5 = enhancedPolls.createPollFromTemplate(
            0, // Governance template
            "Should we implement the new governance framework?",
            options5,
            "Proposal to implement a new governance framework with enhanced features",
            tags5
        );
        console.log("Created poll from template with ID:", pollId5);

        console.log("Test polls created successfully!");
    }

    function setupDelegationExamples() internal {
        console.log("\nSetting up delegation examples...");

        // Example addresses for delegation
        address delegator1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        address delegator2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
        address delegate1 = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;

        // Set up delegations (these would be called by the actual users)
        console.log("Setting up delegation from", delegator1, "to", delegate1);
        console.log("Setting up delegation from", delegator2, "to", delegate1);

        // Note: In a real deployment, these would be called by the actual users
        // For demonstration, we're just logging the intended actions
        console.log("Delegation examples configured!");
    }

    function demonstrateAnalytics() internal {
        console.log("\nDemonstrating analytics features...");

        // Get analytics
        (
            uint256 totalPollsCreated,
            uint256 totalVotesCast,
            uint256 totalUniqueVoters,
            uint256 averageParticipationRate
        ) = enhancedPolls.getAnalytics();

        console.log("Total polls created:", totalPollsCreated);
        console.log("Total votes cast:", totalVotesCast);
        console.log("Total unique voters:", totalUniqueVoters);
        console.log("Average participation rate:", averageParticipationRate);

        // Get category stats
        uint256 govPolls = enhancedPolls.getCategoryStats(EnhancedPolls.PollCategory.GOVERNANCE);
        uint256 techPolls = enhancedPolls.getCategoryStats(EnhancedPolls.PollCategory.TECHNICAL);
        uint256 communityPolls = enhancedPolls.getCategoryStats(EnhancedPolls.PollCategory.COMMUNITY);

        console.log("Governance polls:", govPolls);
        console.log("Technical polls:", techPolls);
        console.log("Community polls:", communityPolls);

        // Get type stats
        uint256 standardPolls = enhancedPolls.getTypeStats(EnhancedPolls.PollType.STANDARD);
        uint256 weightedPolls = enhancedPolls.getTypeStats(EnhancedPolls.PollType.WEIGHTED);
        uint256 quadraticPolls = enhancedPolls.getTypeStats(EnhancedPolls.PollType.QUADRATIC);

        console.log("Standard polls:", standardPolls);
        console.log("Weighted polls:", weightedPolls);
        console.log("Quadratic polls:", quadraticPolls);
    }

    // Helper function to distribute governance tokens for testing
    function distributeTestTokens() public {
        vm.startBroadcast();
        
        // This would typically be called separately or by the contract owner
        address[] memory recipients = new address[](5);
        recipients[0] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil account 0
        recipients[1] = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil account 1
        recipients[2] = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil account 2
        recipients[3] = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Anvil account 3
        recipients[4] = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65; // Anvil account 4

        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 10000 * 1e18; // 10,000 tokens
        amounts[1] = 5000 * 1e18;  // 5,000 tokens
        amounts[2] = 2000 * 1e18;  // 2,000 tokens
        amounts[3] = 1000 * 1e18;  // 1,000 tokens
        amounts[4] = 500 * 1e18;   // 500 tokens

        governanceToken.airdrop(recipients, amounts);
        console.log("Test tokens distributed!");

        vm.stopBroadcast();
    }

    // Function to demonstrate template management
    function demonstrateTemplates() public view {
        console.log("\nDemonstrating poll templates...");

        // Get template information
        (
            uint256 id,
            string memory name,
            string memory description,
            EnhancedPolls.PollType pollType,
            EnhancedPolls.PollCategory category,
            uint256 defaultDuration,
            uint256 defaultMinParticipation,
            bool requiresToken,
            uint256 defaultMinTokenBalance,
            string[] memory defaultTags,
            bool isActive
        ) = enhancedPolls.getPollTemplate(0);

        console.log("Template ID:", id);
        console.log("Template Name:", name);
        console.log("Template Description:", description);
        console.log("Poll Type:", uint8(pollType));
        console.log("Category:", uint8(category));
        console.log("Default Duration:", defaultDuration);
        console.log("Default Min Participation:", defaultMinParticipation);
        console.log("Requires Token:", requiresToken);
        console.log("Default Min Token Balance:", defaultMinTokenBalance);
        console.log("Is Active:", isActive);
    }

    // Function to demonstrate archiving features
    function demonstrateArchiving() public {
        console.log("\nDemonstrating archiving features...");

        // Create a poll for archiving demonstration
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Archive Demo Poll",
            options,
            1 days, // Short duration for demo
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Poll for demonstrating archiving features",
            tags
        );

        console.log("Created demo poll for archiving with ID:", pollId);

        // Close the poll
        enhancedPolls.closePoll(pollId);
        console.log("Poll closed successfully");

        // Note: Archiving would require waiting for the archive delay
        // In a real scenario, this would be done after the delay period
        console.log("Poll ready for archiving after delay period");
    }
}