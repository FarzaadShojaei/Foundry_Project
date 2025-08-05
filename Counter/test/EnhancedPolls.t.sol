// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {EnhancedPolls} from "../src/EnhancedPolls.sol";
import {GovernanceToken} from "../src/GovernanceToken.sol";

contract EnhancedPollsTest is Test {
    EnhancedPolls public enhancedPolls;
    GovernanceToken public governanceToken;

    address public owner = address(1);
    address public voter1 = address(2);
    address public voter2 = address(3);
    address public voter3 = address(4);
    address public delegate1 = address(5);

    function setUp() public {
        // Deploy contracts
        governanceToken = new GovernanceToken();
        enhancedPolls = new EnhancedPolls(address(governanceToken));

        // Setup token balances
        vm.startPrank(address(this));
        governanceToken.transfer(voter1, 10000 * 1e18);
        governanceToken.transfer(voter2, 5000 * 1e18);
        governanceToken.transfer(voter3, 1000 * 1e18);
        governanceToken.transfer(delegate1, 2000 * 1e18);
        vm.stopPrank();
    }

    function test_CreateStandardPoll() public {
        vm.startPrank(owner);

        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        string[] memory tags = new string[](1);
        tags[0] = "test";

        uint256 pollId = enhancedPolls.createPoll(
            "Test Question?",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0, // no min participation
            address(0), // no token required
            0,
            "Test description",
            tags
        );

        assertEq(pollId, 0);
        assertEq(enhancedPolls.pollCount(), 1);

        EnhancedPolls.PollView memory poll = enhancedPolls.getPoll(0);
        assertEq(poll.id, 0);
        assertEq(poll.question, "Test Question?");
        assertEq(poll.options.length, 3);
        assertEq(poll.creator, owner);
        assertTrue(poll.status == EnhancedPolls.PollStatus.ACTIVE);
        assertTrue(poll.pollType == EnhancedPolls.PollType.STANDARD);

        vm.stopPrank();
    }

    function test_CreateWeightedPoll() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](1);
        tags[0] = "governance";

        uint256 pollId = enhancedPolls.createPoll(
            "Governance Proposal?",
            options,
            14 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            5,
            address(governanceToken),
            1000 * 1e18,
            "Important governance decision",
            tags
        );

        EnhancedPolls.PollView memory poll = enhancedPolls.getPoll(pollId);
        assertTrue(poll.pollType == EnhancedPolls.PollType.WEIGHTED);
        assertTrue(poll.category == EnhancedPolls.PollCategory.GOVERNANCE);
        assertEq(poll.minParticipation, 5);

        vm.stopPrank();
    }

    function test_StandardVoting() public {
        // Create a standard poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Option A";
        options[1] = "Option B";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Standard Vote",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Standard voting test",
            tags
        );
        vm.stopPrank();

        // Vote
        vm.prank(voter1);
        enhancedPolls.vote(pollId, 0);

        vm.prank(voter2);
        enhancedPolls.vote(pollId, 1);

        // Check results
        (uint256[] memory votes, uint256 totalVotes, uint256 totalWeight) = enhancedPolls.getPollResults(pollId);
        assertEq(votes[0], 1);
        assertEq(votes[1], 1);
        assertEq(totalVotes, 2);
        assertEq(totalWeight, 2); // Each vote has weight 1 in standard voting
    }

    function test_WeightedVoting() public {
        // Create a weighted poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Weighted Vote",
            options,
            7 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            0,
            address(governanceToken),
            1000 * 1e18,
            "Weighted voting test",
            tags
        );
        vm.stopPrank();

        // Vote with different token balances
        vm.prank(voter1); // 10000 tokens
        enhancedPolls.vote(pollId, 0);

        vm.prank(voter2); // 5000 tokens
        enhancedPolls.vote(pollId, 1);

        // Check results - votes should be weighted by token balance
        (uint256[] memory votes, uint256 totalVotes, uint256 totalWeight) = enhancedPolls.getPollResults(pollId);
        assertEq(votes[0], 10000); // voter1's weight
        assertEq(votes[1], 5000);  // voter2's weight
        assertEq(totalVotes, 2);   // 2 people voted
        assertEq(totalWeight, 15000); // total weight
    }

    function test_QuadraticVoting() public {
        // Create a quadratic poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Option A";
        options[1] = "Option B";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Quadratic Vote",
            options,
            7 days,
            EnhancedPolls.PollType.QUADRATIC,
            EnhancedPolls.PollCategory.FINANCE,
            0,
            address(governanceToken),
            1000 * 1e18,
            "Quadratic voting test",
            tags
        );
        vm.stopPrank();

        // Vote
        vm.prank(voter1); // 10000 tokens -> sqrt(10000) = 100 weight
        enhancedPolls.vote(pollId, 0);

        vm.prank(voter2); // 5000 tokens -> sqrt(5000) ≈ 70 weight
        enhancedPolls.vote(pollId, 1);

        // Check results
        (uint256[] memory votes, uint256 totalVotes, uint256 totalWeight) = enhancedPolls.getPollResults(pollId);
        assertEq(votes[0], 100); // sqrt(10000)
        assertEq(votes[1], 70);  // sqrt(5000)
        assertEq(totalVotes, 2);
    }

    function test_Delegation() public {
        // Create a poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Delegation Test",
            options,
            7 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            0,
            address(governanceToken),
            500 * 1e18,
            "Testing delegation",
            tags
        );
        vm.stopPrank();

        // Set delegation
        vm.prank(voter3);
        enhancedPolls.setDelegate(delegate1, EnhancedPolls.DelegationType.PROXY);

        // Verify delegation
        assertEq(enhancedPolls.getDelegate(voter3), delegate1);
        
        address[] memory delegators = enhancedPolls.getDelegators(delegate1);
        assertEq(delegators.length, 1);
        assertEq(delegators[0], voter3);

        // Check delegation info
        (
            address delegate,
            EnhancedPolls.DelegationType delegationType,
            uint256 delegatedAt,
            uint256 totalDelegatedWeight,
            bool isActive
        ) = enhancedPolls.getDelegationInfo(voter3);
        
        assertEq(delegate, delegate1);
        assertTrue(delegationType == EnhancedPolls.DelegationType.PROXY);
        assertTrue(isActive);

        // Vote as delegate
        vm.prank(delegate1);
        enhancedPolls.voteAsDelegate(pollId, 0, voter3);

        // Check that voter3 is marked as having voted
        assertTrue(enhancedPolls.hasUserVoted(pollId, voter3));

        // Check vote weight is based on voter3's token balance
        (uint256[] memory votes, , ) = enhancedPolls.getPollResults(pollId);
        assertEq(votes[0], 1000); // voter3's token balance / 1e18
    }

    function test_PollTemplates() public {
        vm.startPrank(owner);

        // Test creating poll from template
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](1);
        tags[0] = "custom";

        // Create poll from governance template (template ID 0)
        uint256 pollId = enhancedPolls.createPollFromTemplate(
            0, // governance template
            "Custom Governance Question",
            options,
            "Custom description",
            tags
        );

        EnhancedPolls.PollView memory poll = enhancedPolls.getPoll(pollId);
        assertTrue(poll.pollType == EnhancedPolls.PollType.WEIGHTED);
        assertTrue(poll.category == EnhancedPolls.PollCategory.GOVERNANCE);

        // Test getting template info
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

        assertEq(id, 0);
        assertEq(name, "Governance Proposal");
        assertTrue(pollType == EnhancedPolls.PollType.WEIGHTED);
        assertTrue(category == EnhancedPolls.PollCategory.GOVERNANCE);
        assertTrue(isActive);

        vm.stopPrank();
    }

    function test_PollArchiving() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Archive Test",
            options,
            1 days, // Short duration for testing
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Testing archiving",
            tags
        );

        // Close the poll
        enhancedPolls.closePoll(pollId);

        // Try to archive immediately (should fail)
        vm.expectRevert(EnhancedPolls.PollTooRecentToArchive.selector);
        enhancedPolls.archivePoll(pollId);

        // Fast forward time past archive delay
        vm.warp(block.timestamp + 31 days);

        // Now archive should work
        enhancedPolls.archivePoll(pollId);

        EnhancedPolls.PollView memory poll = enhancedPolls.getPoll(pollId);
        assertTrue(poll.isArchived);
        assertTrue(poll.status == EnhancedPolls.PollStatus.ARCHIVED);

        vm.stopPrank();
    }

    function test_Analytics() public {
        vm.startPrank(owner);

        // Create multiple polls
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        // Create polls in different categories
        enhancedPolls.createPoll(
            "Governance Poll",
            options,
            7 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            0,
            address(governanceToken),
            1000 * 1e18,
            "Governance test",
            tags
        );

        enhancedPolls.createPoll(
            "Community Poll",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.COMMUNITY,
            0,
            address(0),
            0,
            "Community test",
            tags
        );

        vm.stopPrank();

        // Vote on polls
        vm.prank(voter1);
        enhancedPolls.vote(0, 0);

        vm.prank(voter2);
        enhancedPolls.vote(1, 1);

        // Check analytics
        (
            uint256 totalPollsCreated,
            uint256 totalVotesCast,
            uint256 totalUniqueVoters,
            uint256 averageParticipationRate
        ) = enhancedPolls.getAnalytics();

        assertEq(totalPollsCreated, 2);
        assertEq(totalVotesCast, 2);

        // Check category stats
        uint256 govPolls = enhancedPolls.getCategoryStats(EnhancedPolls.PollCategory.GOVERNANCE);
        uint256 communityPolls = enhancedPolls.getCategoryStats(EnhancedPolls.PollCategory.COMMUNITY);
        
        assertEq(govPolls, 1);
        assertEq(communityPolls, 1);

        // Check type stats
        uint256 weightedPolls = enhancedPolls.getTypeStats(EnhancedPolls.PollType.WEIGHTED);
        uint256 standardPolls = enhancedPolls.getTypeStats(EnhancedPolls.PollType.STANDARD);
        
        assertEq(weightedPolls, 1);
        assertEq(standardPolls, 1);
    }

    function test_FrontendHelpers() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        // Create a poll
        uint256 pollId = enhancedPolls.createPoll(
            "Frontend Test",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Testing frontend helpers",
            tags
        );

        // Test getPollSummary
        (
            string memory question,
            uint256 totalVotes,
            uint256 totalWeight,
            EnhancedPolls.PollStatus status,
            bool isActive
        ) = enhancedPolls.getPollSummary(pollId);

        assertEq(question, "Frontend Test");
        assertEq(totalVotes, 0);
        assertEq(totalWeight, 0);
        assertTrue(status == EnhancedPolls.PollStatus.ACTIVE);
        assertTrue(isActive);

        // Test getPollsForFrontend
        (
            uint256[] memory pollIds,
            EnhancedPolls.PollView[] memory pollViews
        ) = enhancedPolls.getPollsForFrontend(
            0, // offset
            10, // limit
            EnhancedPolls.PollStatus.ACTIVE,
            EnhancedPolls.PollCategory.GENERAL
        );

        assertEq(pollIds.length, 1);
        assertEq(pollViews.length, 1);
        assertEq(pollIds[0], pollId);

        vm.stopPrank();
    }

    function test_PollCategories() public {
        vm.startPrank(owner);

        // Create polls in different categories
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        // Governance poll
        enhancedPolls.createPoll(
            "Governance Question",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GOVERNANCE,
            0,
            address(0),
            0,
            "Gov description",
            tags
        );

        // Technical poll
        enhancedPolls.createPoll(
            "Technical Question",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.TECHNICAL,
            0,
            address(0),
            0,
            "Tech description",
            tags
        );

        vm.stopPrank();

        // Check category filtering
        uint256[] memory govPolls = enhancedPolls.getPollsByCategory(EnhancedPolls.PollCategory.GOVERNANCE);
        uint256[] memory techPolls = enhancedPolls.getPollsByCategory(EnhancedPolls.PollCategory.TECHNICAL);

        assertEq(govPolls.length, 1);
        assertEq(techPolls.length, 1);
        assertEq(govPolls[0], 0);
        assertEq(techPolls[0], 1);
    }

    function test_PollTags() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](2);
        tags[0] = "defi";
        tags[1] = "protocol";

        enhancedPolls.createPoll(
            "Tagged Question",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Tagged poll",
            tags
        );

        vm.stopPrank();

        // Check tag filtering
        uint256[] memory defiPolls = enhancedPolls.getPollsByTag("defi");
        uint256[] memory protocolPolls = enhancedPolls.getPollsByTag("protocol");

        assertEq(defiPolls.length, 1);
        assertEq(protocolPolls.length, 1);
        assertEq(defiPolls[0], 0);
        assertEq(protocolPolls[0], 0);
    }

    function test_PollExtension() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Extendable Poll",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Test extension",
            tags
        );

        uint256 originalEndTime = enhancedPolls.getPoll(pollId).endTime;

        // Extend poll by 3 days
        enhancedPolls.extendPoll(pollId, 3 days);

        uint256 newEndTime = enhancedPolls.getPoll(pollId).endTime;
        assertEq(newEndTime, originalEndTime + 3 days);

        vm.stopPrank();
    }

    function test_UserStats() public {
        // Create a poll and vote
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        enhancedPolls.createPoll(
            "Stats Test",
            options,
            7 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(governanceToken),
            1000 * 1e18,
            "Testing user stats",
            tags
        );
        vm.stopPrank();

        vm.prank(voter1);
        enhancedPolls.vote(0, 0);

        // Check user stats
        (uint256 pollsCreated, uint256 pollsVoted, uint256 totalVotingWeight) = enhancedPolls.getUserStats(owner);
        assertEq(pollsCreated, 1);
        assertEq(pollsVoted, 0);

        (pollsCreated, pollsVoted, totalVotingWeight) = enhancedPolls.getUserStats(voter1);
        assertEq(pollsCreated, 0);
        assertEq(pollsVoted, 1);
        assertEq(totalVotingWeight, 10000); // voter1's token balance / 1e18
    }

    function test_RevertAlreadyVoted() public {
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Double Vote Test",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Testing double voting prevention",
            tags
        );
        vm.stopPrank();

        vm.prank(voter1);
        enhancedPolls.vote(pollId, 0);

        vm.prank(voter1);
        vm.expectRevert(EnhancedPolls.AlreadyVoted.selector);
        enhancedPolls.vote(pollId, 1);
    }

    function test_RevertInsufficientTokenBalance() public {
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Token Balance Test",
            options,
            7 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            0,
            address(governanceToken),
            15000 * 1e18, // More than any voter has
            "Testing token requirement",
            tags
        );
        vm.stopPrank();

        vm.prank(voter1); // Only has 10000 tokens
        vm.expectRevert(EnhancedPolls.InsufficientTokenBalance.selector);
        enhancedPolls.vote(pollId, 0);
    }

    function test_BatchVoting() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        // Create multiple polls
        uint256 pollId1 = enhancedPolls.createPoll(
            "Batch Vote 1",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Batch voting test 1",
            tags
        );

        uint256 pollId2 = enhancedPolls.createPoll(
            "Batch Vote 2",
            options,
            7 days,
            EnhancedPolls.PollType.STANDARD,
            EnhancedPolls.PollCategory.GENERAL,
            0,
            address(0),
            0,
            "Batch voting test 2",
            tags
        );

        vm.stopPrank();

        // Batch vote
        uint256[] memory pollIds = new uint256[](2);
        pollIds[0] = pollId1;
        pollIds[1] = pollId2;

        uint256[] memory optionIndices = new uint256[](2);
        optionIndices[0] = 0;
        optionIndices[1] = 1;

        vm.prank(voter1);
        enhancedPolls.batchVote(pollIds, optionIndices);

        // Check results
        (uint256[] memory votes1, , ) = enhancedPolls.getPollResults(pollId1);
        (uint256[] memory votes2, , ) = enhancedPolls.getPollResults(pollId2);

        assertEq(votes1[0], 1); // Voted for option 0
        assertEq(votes2[1], 1); // Voted for option 1
    }

    function test_EnhancedDelegation() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        string[] memory tags = new string[](0);

        uint256 pollId = enhancedPolls.createPoll(
            "Enhanced Delegation Test",
            options,
            7 days,
            EnhancedPolls.PollType.WEIGHTED,
            EnhancedPolls.PollCategory.GOVERNANCE,
            0,
            address(governanceToken),
            500 * 1e18,
            "Testing enhanced delegation",
            tags
        );

        vm.stopPrank();

        // Set delegation with specific type
        vm.prank(voter3);
        enhancedPolls.setDelegate(delegate1, EnhancedPolls.DelegationType.REPRESENTATIVE);

        // Check delegation info
        (
            address delegate,
            EnhancedPolls.DelegationType delegationType,
            uint256 delegatedAt,
            uint256 totalDelegatedWeight,
            bool isActive
        ) = enhancedPolls.getDelegationInfo(voter3);

        assertEq(delegate, delegate1);
        assertTrue(delegationType == EnhancedPolls.DelegationType.REPRESENTATIVE);
        assertTrue(isActive);
        assertEq(totalDelegatedWeight, 0); // No votes yet

        // Vote as delegate
        vm.prank(delegate1);
        enhancedPolls.voteAsDelegate(pollId, 0, voter3);

        // Check updated delegation info
        (delegate, delegationType, delegatedAt, totalDelegatedWeight, isActive) = enhancedPolls.getDelegationInfo(voter3);
        assertEq(totalDelegatedWeight, 1000); // voter3's token balance / 1e18

        // Remove delegation
        vm.prank(voter3);
        enhancedPolls.removeDelegate();

        (delegate, delegationType, delegatedAt, totalDelegatedWeight, isActive) = enhancedPolls.getDelegationInfo(voter3);
        assertFalse(isActive);
    }
}