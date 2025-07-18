// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

contract DecentralizedPolls {
    // Structs
    struct Poll {
        uint256 id;
        string question;
        string[] options;
        mapping(uint256 => uint256) votes; // optionIndex => voteCount
        mapping(address => bool) hasVoted;
        address creator;
        uint256 createdAt;
        uint256 endTime;
        bool isActive;
    }

    // State variables
    uint256 public pollCount;
    mapping(uint256 => Poll) public polls;
    mapping(address => uint256[]) public userCreatedPolls;
    mapping(address => uint256[]) public userVotedPolls;

    // Events
    event PollCreated(
        uint256 indexed pollId,
        address indexed creator,
        string question,
        uint256 endTime
    );

    event VoteCast(
        uint256 indexed pollId,
        address indexed voter,
        uint256 optionIndex
    );

    event PollClosed(uint256 indexed pollId);

    // Errors
    error PollNotFound();
    error PollNotActive();
    error AlreadyVoted();
    error InvalidOption();
    error PollEnded();
    error OnlyCreator();
    error EmptyQuestion();
    error InsufficientOptions();
    error InvalidDuration();

    // Modifiers
    modifier pollExists(uint256 _pollId) {
        if (_pollId >= pollCount) revert PollNotFound();
        _;
    }

    modifier pollActive(uint256 _pollId) {
        if (!polls[_pollId].isActive) revert PollNotActive();
        if (block.timestamp > polls[_pollId].endTime) revert PollEnded();
        _;
    }

    modifier onlyPollCreator(uint256 _pollId) {
        if (polls[_pollId].creator != msg.sender) revert OnlyCreator();
        _;
    }

    // Functions
    function createPoll(
        string memory _question,
        string[] memory _options,
        uint256 _durationInDays
    ) external returns (uint256) {
        if (bytes(_question).length == 0) revert EmptyQuestion();
        if (_options.length < 2) revert InsufficientOptions();
        if (_durationInDays == 0 || _durationInDays > 365) revert InvalidDuration();

        uint256 pollId = pollCount++;
        uint256 endTime = block.timestamp + (_durationInDays * 1 days);

        Poll storage newPoll = polls[pollId];
        newPoll.id = pollId;
        newPoll.question = _question;
        newPoll.options = _options;
        newPoll.creator = msg.sender;
        newPoll.createdAt = block.timestamp;
        newPoll.endTime = endTime;
        newPoll.isActive = true;

        userCreatedPolls[msg.sender].push(pollId);

        emit PollCreated(pollId, msg.sender, _question, endTime);
        return pollId;
    }

    function vote(uint256 _pollId, uint256 _optionIndex)
    external
    pollExists(_pollId)
    pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];

        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        poll.hasVoted[msg.sender] = true;
        poll.votes[_optionIndex]++;

        userVotedPolls[msg.sender].push(_pollId);

        emit VoteCast(_pollId, msg.sender, _optionIndex);
    }

    function closePoll(uint256 _pollId)
    external
    pollExists(_pollId)
    onlyPollCreator(_pollId)
    {
        polls[_pollId].isActive = false;
        emit PollClosed(_pollId);
    }

    // View functions
    function getPoll(uint256 _pollId)
    external
    view
    pollExists(_pollId)
    returns (
        uint256 id,
        string memory question,
        string[] memory options,
        address creator,
        uint256 createdAt,
        uint256 endTime,
        bool isActive
    )
    {
        Poll storage poll = polls[_pollId];
        return (
            poll.id,
            poll.question,
            poll.options,
            poll.creator,
            poll.createdAt,
            poll.endTime,
            poll.isActive && block.timestamp <= poll.endTime
        );
    }

    function getPollResults(uint256 _pollId)
    external
    view
    pollExists(_pollId)
    returns (uint256[] memory votes)
    {
        Poll storage poll = polls[_pollId];
        votes = new uint256[](poll.options.length);

        for (uint256 i = 0; i < poll.options.length; i++) {
            votes[i] = poll.votes[i];
        }
    }

    function hasUserVoted(uint256 _pollId, address _user)
    external
    view
    pollExists(_pollId)
    returns (bool)
    {
        return polls[_pollId].hasVoted[_user];
    }

    function getUserCreatedPolls(address _user)
    external
    view
    returns (uint256[] memory)
    {
        return userCreatedPolls[_user];
    }

    function getUserVotedPolls(address _user)
    external
    view
    returns (uint256[] memory)
    {
        return userVotedPolls[_user];
    }

    function isPollActive(uint256 _pollId)
    external
    view
    pollExists(_pollId)
    returns (bool)
    {
        Poll storage poll = polls[_pollId];
        return poll.isActive && block.timestamp <= poll.endTime;
    }

    function getTotalVotes(uint256 _pollId)
    external
    view
    pollExists(_pollId)
    returns (uint256 total)
    {
        Poll storage poll = polls[_pollId];
        for (uint256 i = 0; i < poll.options.length; i++) {
            total += poll.votes[i];
        }
    }
}