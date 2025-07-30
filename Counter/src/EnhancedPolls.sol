// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EnhancedPolls is Ownable, ReentrancyGuard {
    // Enums
    enum PollType { STANDARD, WEIGHTED, QUADRATIC }
    enum PollCategory { GENERAL, GOVERNANCE, TECHNICAL, COMMUNITY, FINANCE }
    enum PollStatus { ACTIVE, CLOSED, EXPIRED, CANCELLED }

    // Structs
    struct Poll {
        uint256 id;
        string question;
        string[] options;
        mapping(uint256 => uint256) votes; // optionIndex => voteCount
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voterWeight; // For weighted voting
        address creator;
        uint256 createdAt;
        uint256 endTime;
        PollStatus status;
        PollType pollType;
        PollCategory category;
        uint256 minParticipation; // Minimum number of votes required
        uint256 totalVotes;
        uint256 totalWeight; // For weighted voting
        bool requiresToken; // Whether voting requires token holding
        address tokenAddress; // Token contract address for weighted voting
        uint256 minTokenBalance; // Minimum token balance to vote
        string description; // Extended description
        string[] tags; // Poll tags for filtering
    }

    struct PollView {
        uint256 id;
        string question;
        string[] options;
        address creator;
        uint256 createdAt;
        uint256 endTime;
        PollStatus status;
        PollType pollType;
        PollCategory category;
        uint256 minParticipation;
        uint256 totalVotes;
        uint256 totalWeight;
        string description;
        string[] tags;
    }

    // State variables
    uint256 public pollCount;
    mapping(uint256 => Poll) public polls;
    mapping(address => uint256[]) public userCreatedPolls;
    mapping(address => uint256[]) public userVotedPolls;
    mapping(PollCategory => uint256[]) public pollsByCategory;
    mapping(string => uint256[]) public pollsByTag;
    
    // Delegation mappings
    mapping(address => address) public delegates; // user => delegate
    mapping(address => address[]) public delegators; // delegate => users who delegated to them
    
    // Platform settings
    uint256 public platformFee = 0; // Fee in wei to create a poll
    uint256 public maxPollDuration = 365 days;
    uint256 public minPollDuration = 1 hours;
    bool public platformPaused = false;

    // Events
    event PollCreated(
        uint256 indexed pollId,
        address indexed creator,
        string question,
        PollType pollType,
        PollCategory category,
        uint256 endTime,
        string[] tags
    );

    event VoteCast(
        uint256 indexed pollId,
        address indexed voter,
        uint256 optionIndex,
        uint256 weight
    );

    event PollStatusChanged(uint256 indexed pollId, PollStatus newStatus);
    event PollExtended(uint256 indexed pollId, uint256 newEndTime);
    event PlatformSettingsUpdated(uint256 fee, bool paused);
    event DelegateSet(address indexed delegator, address indexed delegate);
    event DelegateRemoved(address indexed delegator, address indexed delegate);

    // Errors
    error PollNotFound();
    error PollNotActive();
    error AlreadyVoted();
    error InvalidOption();
    error OnlyCreator();
    error EmptyQuestion();
    error InsufficientOptions();
    error InvalidDuration();
    error InsufficientTokenBalance();
    error InsufficientFee();
    error PlatformPaused();
    error MinParticipationNotMet();
    error InvalidPollType();
    error InvalidAddress();
    error CannotDelegateToSelf();
    error AlreadyDelegated();
    error NoDelegateSet();

    // Modifiers
    modifier pollExists(uint256 _pollId) {
        if (_pollId >= pollCount) revert PollNotFound();
        _;
    }

    modifier pollActive(uint256 _pollId) {
        Poll storage poll = polls[_pollId];
        if (poll.status != PollStatus.ACTIVE) revert PollNotActive();
        if (block.timestamp > poll.endTime) {
            poll.status = PollStatus.EXPIRED;
            emit PollStatusChanged(_pollId, PollStatus.EXPIRED);
            revert PollNotActive();
        }
        _;
    }

    modifier onlyPollCreator(uint256 _pollId) {
        if (polls[_pollId].creator != msg.sender) revert OnlyCreator();
        _;
    }

    modifier whenNotPaused() {
        if (platformPaused) revert PlatformPaused();
        _;
    }

    constructor() Ownable(msg.sender) {}

    // Core Functions
    function createPoll(
        string memory _question,
        string[] memory _options,
        uint256 _durationInSeconds,
        PollType _pollType,
        PollCategory _category,
        uint256 _minParticipation,
        address _tokenAddress,
        uint256 _minTokenBalance,
        string memory _description,
        string[] memory _tags
    ) external payable nonReentrant whenNotPaused returns (uint256) {
        if (msg.value < platformFee) revert InsufficientFee();
        if (bytes(_question).length == 0) revert EmptyQuestion();
        if (_options.length < 2) revert InsufficientOptions();
        if (_durationInSeconds < minPollDuration || _durationInSeconds > maxPollDuration) 
            revert InvalidDuration();
        if (_pollType == PollType.WEIGHTED && _tokenAddress == address(0)) 
            revert InvalidAddress();

        uint256 pollId = pollCount++;
        uint256 endTime = block.timestamp + _durationInSeconds;

        Poll storage newPoll = polls[pollId];
        newPoll.id = pollId;
        newPoll.question = _question;
        newPoll.options = _options;
        newPoll.creator = msg.sender;
        newPoll.createdAt = block.timestamp;
        newPoll.endTime = endTime;
        newPoll.status = PollStatus.ACTIVE;
        newPoll.pollType = _pollType;
        newPoll.category = _category;
        newPoll.minParticipation = _minParticipation;
        newPoll.requiresToken = _tokenAddress != address(0);
        newPoll.tokenAddress = _tokenAddress;
        newPoll.minTokenBalance = _minTokenBalance;
        newPoll.description = _description;
        newPoll.tags = _tags;

        userCreatedPolls[msg.sender].push(pollId);
        pollsByCategory[_category].push(pollId);
        
        // Index by tags
        for (uint256 i = 0; i < _tags.length; i++) {
            pollsByTag[_tags[i]].push(pollId);
        }

        emit PollCreated(pollId, msg.sender, _question, _pollType, _category, endTime, _tags);
        return pollId;
    }

    function vote(uint256 _pollId, uint256 _optionIndex)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];

        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        uint256 weight = 1;

        // Handle different voting types
        if (poll.pollType == PollType.WEIGHTED || poll.pollType == PollType.QUADRATIC) {
            if (poll.requiresToken) {
                IERC20 token = IERC20(poll.tokenAddress);
                uint256 balance = token.balanceOf(msg.sender);
                if (balance < poll.minTokenBalance) revert InsufficientTokenBalance();
                
                if (poll.pollType == PollType.WEIGHTED) {
                    weight = balance / 1e18; // Assuming 18 decimal token
                    if (weight == 0) weight = 1;
                } else if (poll.pollType == PollType.QUADRATIC) {
                    weight = sqrt(balance / 1e18);
                    if (weight == 0) weight = 1;
                }
            }
        }

        poll.hasVoted[msg.sender] = true;
        poll.voterWeight[msg.sender] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        userVotedPolls[msg.sender].push(_pollId);

        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    function closePoll(uint256 _pollId)
        external
        pollExists(_pollId)
        onlyPollCreator(_pollId)
        nonReentrant
    {
        Poll storage poll = polls[_pollId];
        if (poll.minParticipation > 0 && poll.totalVotes < poll.minParticipation) {
            revert MinParticipationNotMet();
        }
        
        poll.status = PollStatus.CLOSED;
        emit PollStatusChanged(_pollId, PollStatus.CLOSED);
    }

    function extendPoll(uint256 _pollId, uint256 _additionalTime)
        external
        pollExists(_pollId)
        onlyPollCreator(_pollId)
        nonReentrant
    {
        Poll storage poll = polls[_pollId];
        if (poll.status != PollStatus.ACTIVE) revert PollNotActive();
        
        uint256 newEndTime = poll.endTime + _additionalTime;
        if (newEndTime > block.timestamp + maxPollDuration) revert InvalidDuration();
        
        poll.endTime = newEndTime;
        emit PollExtended(_pollId, newEndTime);
    }

    // View functions
    function getPoll(uint256 _pollId)
        external
        view
        pollExists(_pollId)
        returns (PollView memory)
    {
        Poll storage poll = polls[_pollId];
        return PollView({
            id: poll.id,
            question: poll.question,
            options: poll.options,
            creator: poll.creator,
            createdAt: poll.createdAt,
            endTime: poll.endTime,
            status: poll.status,
            pollType: poll.pollType,
            category: poll.category,
            minParticipation: poll.minParticipation,
            totalVotes: poll.totalVotes,
            totalWeight: poll.totalWeight,
            description: poll.description,
            tags: poll.tags
        });
    }

    function getPollResults(uint256 _pollId)
        external
        view
        pollExists(_pollId)
        returns (uint256[] memory votes, uint256 totalVotes, uint256 totalWeight)
    {
        Poll storage poll = polls[_pollId];
        votes = new uint256[](poll.options.length);

        for (uint256 i = 0; i < poll.options.length; i++) {
            votes[i] = poll.votes[i];
        }

        return (votes, poll.totalVotes, poll.totalWeight);
    }

    function getPollsByCategory(PollCategory _category)
        external
        view
        returns (uint256[] memory)
    {
        return pollsByCategory[_category];
    }

    function getPollsByTag(string memory _tag)
        external
        view
        returns (uint256[] memory)
    {
        return pollsByTag[_tag];
    }

    function getActivePollsCount() external view returns (uint256 count) {
        for (uint256 i = 0; i < pollCount; i++) {
            if (polls[i].status == PollStatus.ACTIVE && block.timestamp <= polls[i].endTime) {
                count++;
            }
        }
    }

    function getUserStats(address _user)
        external
        view
        returns (
            uint256 pollsCreated,
            uint256 pollsVoted,
            uint256 totalVotingWeight
        )
    {
        pollsCreated = userCreatedPolls[_user].length;
        pollsVoted = userVotedPolls[_user].length;
        
        for (uint256 i = 0; i < userVotedPolls[_user].length; i++) {
            uint256 pollId = userVotedPolls[_user][i];
            totalVotingWeight += polls[pollId].voterWeight[_user];
        }
    }

    // Admin functions
    function setPlatformSettings(uint256 _fee, bool _paused)
        external
        onlyOwner
    {
        platformFee = _fee;
        platformPaused = _paused;
        emit PlatformSettingsUpdated(_fee, _paused);
    }

    function setDurationLimits(uint256 _minDuration, uint256 _maxDuration)
        external
        onlyOwner
    {
        minPollDuration = _minDuration;
        maxPollDuration = _maxDuration;
    }

    function withdrawFees() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    function emergencyClosePoll(uint256 _pollId)
        external
        onlyOwner
        pollExists(_pollId)
    {
        polls[_pollId].status = PollStatus.CANCELLED;
        emit PollStatusChanged(_pollId, PollStatus.CANCELLED);
    }

    // Delegation functions
    function setDelegate(address _delegate) external {
        if (_delegate == msg.sender) revert CannotDelegateToSelf();
        if (_delegate == address(0)) revert InvalidAddress();
        
        address currentDelegate = delegates[msg.sender];
        if (currentDelegate != address(0)) {
            // Remove from current delegate's list
            _removeDelegator(currentDelegate, msg.sender);
            emit DelegateRemoved(msg.sender, currentDelegate);
        }
        
        delegates[msg.sender] = _delegate;
        delegators[_delegate].push(msg.sender);
        
        emit DelegateSet(msg.sender, _delegate);
    }
    
    function removeDelegate() external {
        address currentDelegate = delegates[msg.sender];
        if (currentDelegate == address(0)) revert NoDelegateSet();
        
        _removeDelegator(currentDelegate, msg.sender);
        delegates[msg.sender] = address(0);
        
        emit DelegateRemoved(msg.sender, currentDelegate);
    }
    
    function voteAsDelegate(uint256 _pollId, uint256 _optionIndex, address _delegator)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        if (delegates[_delegator] != msg.sender) revert OnlyCreator(); // Reusing error
        
        Poll storage poll = polls[_pollId];
        if (poll.hasVoted[_delegator]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        uint256 weight = 1;

        // Handle different voting types using delegator's token balance
        if (poll.pollType == PollType.WEIGHTED || poll.pollType == PollType.QUADRATIC) {
            if (poll.requiresToken) {
                IERC20 token = IERC20(poll.tokenAddress);
                uint256 balance = token.balanceOf(_delegator);
                if (balance < poll.minTokenBalance) revert InsufficientTokenBalance();
                
                if (poll.pollType == PollType.WEIGHTED) {
                    weight = balance / 1e18;
                    if (weight == 0) weight = 1;
                } else if (poll.pollType == PollType.QUADRATIC) {
                    weight = sqrt(balance / 1e18);
                    if (weight == 0) weight = 1;
                }
            }
        }

        poll.hasVoted[_delegator] = true;
        poll.voterWeight[_delegator] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        userVotedPolls[_delegator].push(_pollId);

        emit VoteCast(_pollId, _delegator, _optionIndex, weight);
    }
    
    function getDelegators(address _delegate) external view returns (address[] memory) {
        return delegators[_delegate];
    }
    
    function getDelegate(address _user) external view returns (address) {
        return delegates[_user];
    }
    
    function _removeDelegator(address _delegate, address _delegator) internal {
        address[] storage delegatorList = delegators[_delegate];
        for (uint256 i = 0; i < delegatorList.length; i++) {
            if (delegatorList[i] == _delegator) {
                delegatorList[i] = delegatorList[delegatorList.length - 1];
                delegatorList.pop();
                break;
            }
        }
    }

    // Utility functions
    function sqrt(uint256 x) internal pure returns (uint256) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        uint256 y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    // Legacy compatibility functions
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
        return poll.status == PollStatus.ACTIVE && block.timestamp <= poll.endTime;
    }

    // Additional utility function for CLI compatibility
    function getTotalVotes(uint256 _pollId)
        external
        view
        pollExists(_pollId)
        returns (uint256)
    {
        return polls[_pollId].totalVotes;
    }

    // Batch voting function for efficiency
    function batchVote(uint256[] calldata _pollIds, uint256[] calldata _optionIndices)
        external
        nonReentrant
    {
        if (_pollIds.length != _optionIndices.length) revert InvalidAddress(); // Reusing error
        
        for (uint256 i = 0; i < _pollIds.length; i++) {
            // Internal vote logic would go here, but for simplicity calling the main vote function
            this.vote(_pollIds[i], _optionIndices[i]);
        }
    }

    // Get polls by multiple criteria
    function getFilteredPolls(
        PollStatus _status,
        PollCategory _category,
        bool _activeOnly
    ) external view returns (uint256[] memory) {
        uint256[] memory categoryPolls = pollsByCategory[_category];
        uint256[] memory filtered = new uint256[](categoryPolls.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < categoryPolls.length; i++) {
            uint256 pollId = categoryPolls[i];
            Poll storage poll = polls[pollId];
            
            bool matchesStatus = (_status == poll.status);
            bool isActive = poll.status == PollStatus.ACTIVE && block.timestamp <= poll.endTime;
            bool matchesActiveFilter = !_activeOnly || isActive;
            
            if (matchesStatus && matchesActiveFilter) {
                filtered[count] = pollId;
                count++;
            }
        }
        
        // Resize array to actual count
        uint256[] memory result = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = filtered[i];
        }
        
        return result;
    }
} 