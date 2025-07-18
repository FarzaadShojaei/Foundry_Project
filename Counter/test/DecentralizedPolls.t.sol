// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedPolls} from "../src/DecentralizedPolls.sol";

contract DecentralizedPollsTest is Test {
    DecentralizedPolls public polls;

    address public owner = address(1);
    address public voter1 = address(2);
    address public voter2 = address(3);

    function setUp() public {
        polls = new DecentralizedPolls();
    }

    function test_CreatePoll() public {
        vm.startPrank(owner);

        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";

        uint256 pollId = polls.createPoll("Test Question?", options, 7);

        assertEq(pollId, 0);
        assertEq(polls.pollCount(), 1);

        (
            uint256 id,
            string memory question,
            string[] memory pollOptions,
            address creator,
            uint256 createdAt,
            uint256 endTime,
            bool isActive
        ) = polls.getPoll(0);

        assertEq(id, 0);
        assertEq(question, "Test Question?");
        assertEq(pollOptions.length, 3);
        assertEq(creator, owner);
        assertTrue(isActive);
        assertEq(endTime, block.timestamp + 7 days);

        vm.stopPrank();
    }

    function test_CreatePollWithEmptyQuestion() public {
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        vm.expectRevert(DecentralizedPolls.EmptyQuestion.selector);
        polls.createPoll("", options, 7);
    }

    function test_CreatePollWithInsufficientOptions() public {
        string[] memory options = new string[](1);
        options[0] = "Only Option";

        vm.expectRevert(DecentralizedPolls.InsufficientOptions.selector);
        polls.createPoll("Test Question?", options, 7);
    }

    function test_CreatePollWithInvalidDuration() public {
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        vm.expectRevert(DecentralizedPolls.InvalidDuration.selector);
        polls.createPoll("Test Question?", options, 0);

        vm.expectRevert(DecentralizedPolls.InvalidDuration.selector);
        polls.createPoll("Test Question?", options, 366);
    }

    function test_Vote() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);
        vm.stopPrank();

        // Vote
        vm.startPrank(voter1);
        polls.vote(pollId, 0);
        vm.stopPrank();

        assertTrue(polls.hasUserVoted(pollId, voter1));

        uint256[] memory results = polls.getPollResults(pollId);
        assertEq(results[0], 1);
        assertEq(results[1], 0);

        assertEq(polls.getTotalVotes(pollId), 1);
    }

    function test_VoteMultipleUsers() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](3);
        options[0] = "Option A";
        options[1] = "Option B";
        options[2] = "Option C";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);
        vm.stopPrank();

        // Multiple votes
        vm.prank(voter1);
        polls.vote(pollId, 0);

        vm.prank(voter2);
        polls.vote(pollId, 1);

        vm.prank(address(4));
        polls.vote(pollId, 0);

        uint256[] memory results = polls.getPollResults(pollId);
        assertEq(results[0], 2); // Option A
        assertEq(results[1], 1); // Option B
        assertEq(results[2], 0); // Option C

        assertEq(polls.getTotalVotes(pollId), 3);
    }

    function test_VoteAlreadyVoted() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);
        vm.stopPrank();

        // First vote
        vm.startPrank(voter1);
        polls.vote(pollId, 0);

        // Second vote should fail
        vm.expectRevert(DecentralizedPolls.AlreadyVoted.selector);
        polls.vote(pollId, 1);
        vm.stopPrank();
    }

    function test_VoteInvalidOption() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);
        vm.stopPrank();

        // Vote with invalid option
        vm.startPrank(voter1);
        vm.expectRevert(DecentralizedPolls.InvalidOption.selector);
        polls.vote(pollId, 2);
        vm.stopPrank();
    }

    function test_VoteOnNonExistentPoll() public {
        vm.startPrank(voter1);
        vm.expectRevert(DecentralizedPolls.PollNotFound.selector);
        polls.vote(999, 0);
        vm.stopPrank();
    }

    function test_VoteOnExpiredPoll() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);
        vm.stopPrank();

        // Fast forward time beyond poll end
        vm.warp(block.timestamp + 8 days);

        // Vote should fail
        vm.startPrank(voter1);
        vm.expectRevert(DecentralizedPolls.PollEnded.selector);
        polls.vote(pollId, 0);
        vm.stopPrank();
    }

    function test_ClosePoll() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);

        // Close poll
        polls.closePoll(pollId);
        vm.stopPrank();

        assertFalse(polls.isPollActive(pollId));

        // Vote should fail on closed poll
        vm.startPrank(voter1);
        vm.expectRevert(DecentralizedPolls.PollNotActive.selector);
        polls.vote(pollId, 0);
        vm.stopPrank();
    }

    function test_ClosePollOnlyCreator() public {
        // Create poll
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";
        uint256 pollId = polls.createPoll("Test Question?", options, 7);
        vm.stopPrank();

        // Try to close poll as non-creator
        vm.startPrank(voter1);
        vm.expectRevert(DecentralizedPolls.OnlyCreator.selector);
        polls.closePoll(pollId);
        vm.stopPrank();
    }

    function test_GetUserCreatedPolls() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        polls.createPoll("Question 1?", options, 7);
        polls.createPoll("Question 2?", options, 7);

        uint256[] memory createdPolls = polls.getUserCreatedPolls(owner);
        assertEq(createdPolls.length, 2);
        assertEq(createdPolls[0], 0);
        assertEq(createdPolls[1], 1);

        vm.stopPrank();
    }

    function test_GetUserVotedPolls() public {
        // Create polls
        vm.startPrank(owner);
        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        polls.createPoll("Question 1?", options, 7);
        polls.createPoll("Question 2?", options, 7);
        vm.stopPrank();

        // Vote on both polls
        vm.startPrank(voter1);
        polls.vote(0, 0);
        polls.vote(1, 1);

        uint256[] memory votedPolls = polls.getUserVotedPolls(voter1);
        assertEq(votedPolls.length, 2);
        assertEq(votedPolls[0], 0);
        assertEq(votedPolls[1], 1);

        vm.stopPrank();
    }

    function test_Events() public {
        vm.startPrank(owner);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        // Test PollCreated event
        vm.expectEmit(true, true, false, true);
        emit DecentralizedPolls.PollCreated(0, owner, "Test Question?", block.timestamp + 7 days);
        uint256 pollId = polls.createPoll("Test Question?", options, 7);

        vm.stopPrank();

        // Test VoteCast event
        vm.startPrank(voter1);
        vm.expectEmit(true, true, false, true);
        emit DecentralizedPolls.VoteCast(pollId, voter1, 0);
        polls.vote(pollId, 0);
        vm.stopPrank();

        // Test PollClosed event
        vm.startPrank(owner);
        vm.expectEmit(true, false, false, true);
        emit DecentralizedPolls.PollClosed(pollId);
        polls.closePoll(pollId);
        vm.stopPrank();
    }

    function testFuzz_CreatePoll(uint256 duration) public {
        vm.assume(duration > 0 && duration <= 365);

        string[] memory options = new string[](2);
        options[0] = "Yes";
        options[1] = "No";

        uint256 pollId = polls.createPoll("Fuzz Question?", options, duration);

        (, , , , , uint256 endTime, bool isActive) = polls.getPoll(pollId);
        assertEq(endTime, block.timestamp + duration * 1 days);
        assertTrue(isActive);
    }

    function testFuzz_Vote(uint256 optionIndex) public {
        // Create poll with 5 options
        string[] memory options = new string[](5);
        options[0] = "Option 0";
        options[1] = "Option 1";
        options[2] = "Option 2";
        options[3] = "Option 3";
        options[4] = "Option 4";

        uint256 pollId = polls.createPoll("Fuzz Question?", options, 7);

        vm.startPrank(voter1);

        if (optionIndex >= 5) {
            vm.expectRevert(DecentralizedPolls.InvalidOption.selector);
            polls.vote(pollId, optionIndex);
        } else {
            polls.vote(pollId, optionIndex);
            uint256[] memory results = polls.getPollResults(pollId);
            assertEq(results[optionIndex], 1);
        }

        vm.stopPrank();
    }
}