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
        enhancedPolls = new EnhancedPolls();
        governanceToken = new GovernanceToken();

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
        enhancedPolls.setDelegate(delegate1);

        // Verify delegation
        assertEq(enhancedPolls.getDelegate(voter3), delegate1);
        
        address[] memory delegators = enhancedPolls.getDelegators(delegate1);
        assertEq(delegators.length, 1);
        assertEq(delegators[0], voter3);

        // Vote as delegate
        vm.prank(delegate1);
        enhancedPolls.voteAsDelegate(pollId, 0, voter3);

        // Check that voter3 is marked as having voted
        assertTrue(enhancedPolls.hasUserVoted(pollId, voter3));

        // Check vote weight is based on voter3's token balance
        (uint256[] memory votes, , ) = enhancedPolls.getPollResults(pollId);
        assertEq(votes[0], 1000); // voter3's token balance / 1e18
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
}