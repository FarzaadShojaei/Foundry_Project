// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EnhancedPolls is Ownable, ReentrancyGuard {
    // Enums
    enum PollType { STANDARD, WEIGHTED, QUADRATIC, RANKED_CHOICE, APPROVAL, LIQUID_DEMOCRACY, TIME_WEIGHTED, REPUTATION_BASED }
    enum PollCategory { GENERAL, GOVERNANCE, TECHNICAL, COMMUNITY, FINANCE }
    enum PollStatus { ACTIVE, CLOSED, EXPIRED, CANCELLED, ARCHIVED }
    enum DelegationType { NONE, PROXY, REPRESENTATIVE }

    // Structs
    struct Poll {
        uint256 id;
        string question;
        string[] options;
        mapping(uint256 => uint256) votes; // optionIndex => voteCount
        mapping(address => bool) hasVoted;
        mapping(address => uint256) voterWeight; // For weighted voting
        mapping(address => uint256[]) rankedChoices; // For ranked choice voting
        mapping(address => bool[]) approvalVotes; // For approval voting
        mapping(address => address) liquidDelegation; // For liquid democracy
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
        uint256 templateId; // Reference to poll template
        bool isArchived;
        uint256 archivedAt;
        uint256 eliminationRound; // For ranked choice voting
        mapping(uint256 => bool) eliminatedOptions; // For ranked choice voting
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
        uint256 templateId;
        bool isArchived;
        uint256 archivedAt;
    }

    struct PollTemplate {
        uint256 id;
        string name;
        string description;
        PollType pollType;
        PollCategory category;
        uint256 defaultDuration;
        uint256 defaultMinParticipation;
        bool requiresToken;
        uint256 defaultMinTokenBalance;
        string[] defaultTags;
        bool isActive;
    }

    struct DelegationInfo {
        address delegate;
        DelegationType delegationType;
        uint256 delegatedAt;
        uint256 totalDelegatedWeight;
        bool isActive;
    }

    struct Analytics {
        uint256 totalPollsCreated;
        uint256 totalVotesCast;
        uint256 totalUniqueVoters;
        uint256 averageParticipationRate;
        mapping(PollCategory => uint256) pollsByCategory;
        mapping(PollType => uint256) pollsByType;
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
    mapping(address => DelegationInfo) public delegationInfo;
    
    // Template system
    uint256 public templateCount;
    mapping(uint256 => PollTemplate) public pollTemplates;
    
    // Analytics
    Analytics public analytics;
    
    // Platform settings
    uint256 public platformFee = 0; // Fee in wei to create a poll
    uint256 public maxPollDuration = 365 days;
    uint256 public minPollDuration = 1 hours;
    bool public platformPaused = false;
    uint256 public archiveDelay = 30 days; // Time before polls can be archived
    address public defaultTokenAddress; // Default token address for templates
    
    // Snapshot functionality
    struct Snapshot {
        uint256 blockNumber;
        mapping(address => uint256) balances;
        mapping(address => uint256) votingPower;
        bool exists;
    }
    
    mapping(uint256 => Snapshot) public snapshots; // pollId => Snapshot
    mapping(address => mapping(uint256 => uint256)) public historicalBalances; // token => blockNumber => balance
    
    // Multi-token support
    struct TokenConfig {
        address tokenAddress;
        uint256 weight; // Weight multiplier for this token (scaled by 1e18)
        uint256 minBalance;
        bool isActive;
    }
    
    mapping(PollCategory => TokenConfig[]) public categoryTokens; // category => supported tokens
    mapping(uint256 => address[]) public pollTokens; // pollId => token addresses used
    
    // Time-weighted voting
    struct TimeWeightConfig {
        uint256 baseMultiplier; // Base multiplier (scaled by 1e18)
        uint256 timeBonus; // Bonus per day of holding (scaled by 1e18)
        uint256 maxMultiplier; // Maximum multiplier cap (scaled by 1e18)
        uint256 minHoldingTime; // Minimum holding time in seconds
    }
    
    mapping(address => mapping(address => uint256)) public tokenFirstSeen; // user => token => timestamp
    mapping(uint256 => TimeWeightConfig) public pollTimeWeights; // pollId => time weight config
    
    // Reputation system
    struct UserReputation {
        uint256 totalVotes; // Total number of votes cast
        uint256 pollsCreated; // Total polls created
        uint256 successfulPolls; // Polls that met minimum participation
        uint256 reputationScore; // Calculated reputation score
        uint256 lastActivityTime; // Last time user was active
        bool isActive; // Whether user is considered active
    }
    
    struct ReputationConfig {
        uint256 votePoints; // Points per vote cast
        uint256 createPoints; // Points per poll created
        uint256 successPoints; // Points per successful poll
        uint256 decayRate; // Reputation decay per day (scaled by 1e18)
        uint256 minActivityTime; // Minimum time between activities
        uint256 maxReputation; // Maximum reputation cap
    }
    
    mapping(address => UserReputation) public userReputations;
    ReputationConfig public reputationConfig;
    
    // Reward system
    struct RewardPool {
        uint256 totalRewards; // Total ETH rewards available
        uint256 creatorRewardPercentage; // Percentage for poll creators (scaled by 100)
        uint256 voterRewardPercentage; // Percentage for voters (scaled by 100)
        uint256 minParticipationForReward; // Minimum votes to qualify for rewards
        bool isActive; // Whether rewards are active
    }
    
    struct UserRewards {
        uint256 totalEarned; // Total rewards earned
        uint256 pendingRewards; // Rewards ready to claim
        uint256 lastClaimTime; // Last time rewards were claimed
        uint256 pollsRewarded; // Number of polls that earned rewards
    }
    
    RewardPool public rewardPool;
    mapping(address => UserRewards) public userRewards;
    mapping(uint256 => uint256) public pollRewardAllocations; // pollId => reward amount

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
    event PollTemplateCreated(uint256 indexed templateId, string name);
    event PollArchived(uint256 indexed pollId);
    event AnalyticsUpdated(uint256 totalPolls, uint256 totalVotes);
    event SnapshotCreated(uint256 indexed pollId, uint256 blockNumber);
    event VotingPowerSnapshot(address indexed user, uint256 indexed pollId, uint256 votingPower);
    event TokenConfigAdded(PollCategory indexed category, address indexed token, uint256 weight);
    event TokenConfigUpdated(PollCategory indexed category, address indexed token, uint256 weight, bool isActive);
    event TimeWeightConfigSet(uint256 indexed pollId, uint256 baseMultiplier, uint256 timeBonus, uint256 maxMultiplier);
    event TokenHoldingTracked(address indexed user, address indexed token, uint256 timestamp);
    event ReputationUpdated(address indexed user, uint256 newScore, uint256 totalVotes, uint256 pollsCreated);
    event ReputationConfigUpdated(uint256 votePoints, uint256 createPoints, uint256 successPoints);
    event RewardPoolUpdated(uint256 totalRewards, uint256 creatorPercentage, uint256 voterPercentage);
    event RewardsDistributed(uint256 indexed pollId, uint256 totalAmount, uint256 creatorAmount, uint256 voterAmount);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardPoolFunded(uint256 amount);

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
    error TemplateNotFound();
    error TemplateNotActive();
    error PollTooRecentToArchive();
    error InvalidDelegationType();

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

    modifier templateExists(uint256 _templateId) {
        if (_templateId >= templateCount) revert TemplateNotFound();
        _;
    }

    constructor(address _defaultTokenAddress) Ownable(msg.sender) {
        defaultTokenAddress = _defaultTokenAddress;
        _initializeReputationSystem();
        _initializeRewardSystem();
        _createDefaultTemplates();
    }

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

        // Update analytics
        analytics.totalPollsCreated++;
        analytics.pollsByCategory[_category]++;
        analytics.pollsByType[_pollType]++;

        // Update user reputation for poll creation
        _updateUserReputation(msg.sender, false, true);

        emit PollCreated(pollId, msg.sender, _question, _pollType, _category, endTime, _tags);
        return pollId;
    }

    function createPollFromTemplate(
        uint256 _templateId,
        string memory _question,
        string[] memory _options,
        string memory _description,
        string[] memory _tags
    ) external payable nonReentrant whenNotPaused returns (uint256) {
        PollTemplate storage template = pollTemplates[_templateId];
        if (!template.isActive) revert TemplateNotActive();

        // Direct poll creation logic to avoid reentrancy
        if (msg.value < platformFee) revert InsufficientFee();
        if (bytes(_question).length == 0) revert EmptyQuestion();
        if (_options.length < 2) revert InsufficientOptions();
        if (template.defaultDuration < minPollDuration || template.defaultDuration > maxPollDuration) 
            revert InvalidDuration();
        if (template.pollType == PollType.WEIGHTED && template.requiresToken && defaultTokenAddress == address(0)) 
            revert InvalidAddress();

        uint256 pollId = pollCount++;
        uint256 endTime = block.timestamp + template.defaultDuration;

        Poll storage newPoll = polls[pollId];
        newPoll.id = pollId;
        newPoll.question = _question;
        newPoll.options = _options;
        newPoll.creator = msg.sender;
        newPoll.createdAt = block.timestamp;
        newPoll.endTime = endTime;
        newPoll.status = PollStatus.ACTIVE;
        newPoll.pollType = template.pollType;
        newPoll.category = template.category;
        newPoll.minParticipation = template.defaultMinParticipation;
        newPoll.requiresToken = template.requiresToken;
        newPoll.tokenAddress = template.requiresToken ? defaultTokenAddress : address(0);
        newPoll.minTokenBalance = template.defaultMinTokenBalance;
        newPoll.description = _description;
        newPoll.tags = _tags.length > 0 ? _tags : template.defaultTags;
        newPoll.templateId = _templateId;

        userCreatedPolls[msg.sender].push(pollId);
        pollsByCategory[template.category].push(pollId);
        
        // Index by tags
        string[] memory finalTags = _tags.length > 0 ? _tags : template.defaultTags;
        for (uint256 i = 0; i < finalTags.length; i++) {
            pollsByTag[finalTags[i]].push(pollId);
        }

        // Update analytics
        analytics.totalPollsCreated++;
        analytics.pollsByCategory[template.category]++;
        analytics.pollsByType[template.pollType]++;

        // Update user reputation for poll creation
        _updateUserReputation(msg.sender, false, true);

        emit PollCreated(pollId, msg.sender, _question, template.pollType, template.category, endTime, finalTags);
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

        // Update analytics
        analytics.totalVotesCast++;

        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    // Ranked Choice Voting
    function voteRankedChoice(uint256 _pollId, uint256[] memory _rankedChoices)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.RANKED_CHOICE) revert InvalidPollType();
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_rankedChoices.length == 0 || _rankedChoices.length > poll.options.length) revert InvalidOption();

        // Validate ranked choices
        bool[] memory usedOptions = new bool[](poll.options.length);
        for (uint256 i = 0; i < _rankedChoices.length; i++) {
            if (_rankedChoices[i] >= poll.options.length) revert InvalidOption();
            if (usedOptions[_rankedChoices[i]]) revert InvalidOption(); // Duplicate choice
            usedOptions[_rankedChoices[i]] = true;
        }

        poll.hasVoted[msg.sender] = true;
        poll.rankedChoices[msg.sender] = _rankedChoices;
        poll.totalVotes++;

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        emit VoteCast(_pollId, msg.sender, _rankedChoices[0], 1); // First choice for event
    }

    // Approval Voting
    function voteApproval(uint256 _pollId, bool[] memory _approvals)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.APPROVAL) revert InvalidPollType();
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_approvals.length != poll.options.length) revert InvalidOption();

        uint256 approvalCount = 0;
        for (uint256 i = 0; i < _approvals.length; i++) {
            if (_approvals[i]) {
                poll.votes[i]++;
                approvalCount++;
            }
        }

        if (approvalCount == 0) revert InvalidOption(); // Must approve at least one option

        poll.hasVoted[msg.sender] = true;
        poll.approvalVotes[msg.sender] = _approvals;
        poll.totalVotes++;

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        emit VoteCast(_pollId, msg.sender, 0, approvalCount); // Use approval count as weight
    }

    // Liquid Democracy Voting
    function voteLiquidDemocracy(uint256 _pollId, uint256 _optionIndex, address _delegate)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.LIQUID_DEMOCRACY) revert InvalidPollType();
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        uint256 weight = 1;

        // Calculate voting weight including delegated votes
        weight += _calculateDelegatedWeight(_pollId, msg.sender);

        // Handle token-based weight
        if (poll.requiresToken) {
            IERC20 token = IERC20(poll.tokenAddress);
            uint256 balance = token.balanceOf(msg.sender);
            if (balance < poll.minTokenBalance) revert InsufficientTokenBalance();
            weight = (weight * balance) / 1e18;
            if (weight == 0) weight = 1;
        }

        poll.hasVoted[msg.sender] = true;
        poll.voterWeight[msg.sender] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        // Set delegation for this poll
        if (_delegate != address(0) && _delegate != msg.sender) {
            poll.liquidDelegation[msg.sender] = _delegate;
        }

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    // Calculate delegated weight for liquid democracy
    function _calculateDelegatedWeight(uint256 _pollId, address _voter) internal view returns (uint256) {
        Poll storage poll = polls[_pollId];
        uint256 delegatedWeight = 0;
        
        // Count direct delegations to this voter
        for (uint256 i = 0; i < userVotedPolls[_voter].length; i++) {
            // This is a simplified version - in practice, you'd need to track delegations more efficiently
        }
        
        return delegatedWeight;
    }

    // Ranked Choice Voting - Calculate results with elimination rounds
    function calculateRankedChoiceResults(uint256 _pollId)
        external
        pollExists(_pollId)
        returns (uint256 winner)
    {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.RANKED_CHOICE) revert InvalidPollType();
        if (poll.status != PollStatus.CLOSED && poll.status != PollStatus.EXPIRED) revert PollNotActive();

        uint256[] memory voteCounts = new uint256[](poll.options.length);
        uint256 totalValidVotes = 0;

        // Count first-choice votes for non-eliminated options
        for (uint256 i = 0; i < poll.totalVotes; i++) {
            // This is a simplified version - would need proper voter iteration
            // voteCounts[poll.rankedChoices[voter][0]]++;
            totalValidVotes++;
        }

        // Check if any option has majority (>50%)
        uint256 majority = (totalValidVotes * 50) / 100 + 1;
        for (uint256 i = 0; i < poll.options.length; i++) {
            if (!poll.eliminatedOptions[i] && voteCounts[i] >= majority) {
                return i; // Winner found
            }
        }

        // Eliminate option with fewest votes
        uint256 minVotes = type(uint256).max;
        uint256 eliminateOption = type(uint256).max;
        
        for (uint256 i = 0; i < poll.options.length; i++) {
            if (!poll.eliminatedOptions[i] && voteCounts[i] < minVotes) {
                minVotes = voteCounts[i];
                eliminateOption = i;
            }
        }

        if (eliminateOption != type(uint256).max) {
            poll.eliminatedOptions[eliminateOption] = true;
            poll.eliminationRound++;
        }

        return type(uint256).max; // No winner yet, need another round
    }

    // Get ranked choice voting details
    function getRankedChoiceDetails(uint256 _pollId, address _voter)
        external
        view
        pollExists(_pollId)
        returns (uint256[] memory rankedChoices, uint256 eliminationRound, bool[] memory eliminatedOptions)
    {
        Poll storage poll = polls[_pollId];
        rankedChoices = poll.rankedChoices[_voter];
        eliminationRound = poll.eliminationRound;
        eliminatedOptions = new bool[](poll.options.length);
        
        for (uint256 i = 0; i < poll.options.length; i++) {
            eliminatedOptions[i] = poll.eliminatedOptions[i];
        }
    }

    // Get approval voting details
    function getApprovalDetails(uint256 _pollId, address _voter)
        external
        view
        pollExists(_pollId)
        returns (bool[] memory approvals)
    {
        Poll storage poll = polls[_pollId];
        return poll.approvalVotes[_voter];
    }

    // Get liquid democracy delegation for a poll
    function getLiquidDemocracyDelegate(uint256 _pollId, address _voter)
        external
        view
        pollExists(_pollId)
        returns (address delegate)
    {
        Poll storage poll = polls[_pollId];
        return poll.liquidDelegation[_voter];
    }

    // Snapshot Functions
    function createSnapshot(uint256 _pollId) external pollExists(_pollId) onlyPollCreator(_pollId) {
        Poll storage poll = polls[_pollId];
        if (poll.status != PollStatus.ACTIVE) revert PollNotActive();
        
        Snapshot storage snapshot = snapshots[_pollId];
        snapshot.blockNumber = block.number;
        snapshot.exists = true;
        
        emit SnapshotCreated(_pollId, block.number);
    }

    function getSnapshotVotingPower(uint256 _pollId, address _user) 
        external 
        view 
        pollExists(_pollId) 
        returns (uint256) 
    {
        Snapshot storage snapshot = snapshots[_pollId];
        if (!snapshot.exists) return 0;
        
        Poll storage poll = polls[_pollId];
        if (!poll.requiresToken) return 1;
        
        // Get historical balance at snapshot block
        uint256 balance = historicalBalances[poll.tokenAddress][snapshot.blockNumber];
        if (balance == 0) {
            // Fallback to current balance if historical not available
            IERC20 token = IERC20(poll.tokenAddress);
            balance = token.balanceOf(_user);
        }
        
        if (poll.pollType == PollType.WEIGHTED) {
            return balance / 1e18;
        } else if (poll.pollType == PollType.QUADRATIC) {
            return sqrt(balance / 1e18);
        }
        
        return 1;
    }

    function recordHistoricalBalance(address _token, address _user, uint256 _balance) 
        external 
        onlyOwner 
    {
        historicalBalances[_token][block.number] = _balance;
    }

    function voteWithSnapshot(uint256 _pollId, uint256 _optionIndex)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        uint256 weight = 1;
        
        // Use snapshot voting power if available
        Snapshot storage snapshot = snapshots[_pollId];
        if (snapshot.exists) {
            weight = this.getSnapshotVotingPower(_pollId, msg.sender);
            if (weight == 0) weight = 1;
        } else {
            // Fallback to regular voting weight calculation
            if (poll.pollType == PollType.WEIGHTED || poll.pollType == PollType.QUADRATIC) {
                if (poll.requiresToken) {
                    IERC20 token = IERC20(poll.tokenAddress);
                    uint256 balance = token.balanceOf(msg.sender);
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
        }

        poll.hasVoted[msg.sender] = true;
        poll.voterWeight[msg.sender] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        emit VotingPowerSnapshot(msg.sender, _pollId, weight);
        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    // Multi-token Functions
    function addTokenConfig(
        PollCategory _category,
        address _tokenAddress,
        uint256 _weight,
        uint256 _minBalance
    ) external onlyOwner {
        TokenConfig memory config = TokenConfig({
            tokenAddress: _tokenAddress,
            weight: _weight,
            minBalance: _minBalance,
            isActive: true
        });
        
        categoryTokens[_category].push(config);
        emit TokenConfigAdded(_category, _tokenAddress, _weight);
    }

    function updateTokenConfig(
        PollCategory _category,
        uint256 _tokenIndex,
        uint256 _weight,
        uint256 _minBalance,
        bool _isActive
    ) external onlyOwner {
        TokenConfig storage config = categoryTokens[_category][_tokenIndex];
        config.weight = _weight;
        config.minBalance = _minBalance;
        config.isActive = _isActive;
        
        emit TokenConfigUpdated(_category, config.tokenAddress, _weight, _isActive);
    }

    function getTokenConfigs(PollCategory _category) 
        external 
        view 
        returns (TokenConfig[] memory) 
    {
        return categoryTokens[_category];
    }

    function calculateMultiTokenWeight(address _voter, PollCategory _category) 
        public 
        view 
        returns (uint256 totalWeight) 
    {
        TokenConfig[] memory tokens = categoryTokens[_category];
        totalWeight = 0;
        
        for (uint256 i = 0; i < tokens.length; i++) {
            if (!tokens[i].isActive) continue;
            
            IERC20 token = IERC20(tokens[i].tokenAddress);
            uint256 balance = token.balanceOf(_voter);
            
            if (balance >= tokens[i].minBalance) {
                uint256 tokenWeight = (balance * tokens[i].weight) / 1e18;
                totalWeight += tokenWeight;
            }
        }
        
        if (totalWeight == 0) totalWeight = 1; // Minimum weight
    }

    function voteMultiToken(uint256 _pollId, uint256 _optionIndex)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        uint256 weight = calculateMultiTokenWeight(msg.sender, poll.category);

        poll.hasVoted[msg.sender] = true;
        poll.voterWeight[msg.sender] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    // Time-Weighted Voting Functions
    function setTimeWeightConfig(
        uint256 _pollId,
        uint256 _baseMultiplier,
        uint256 _timeBonus,
        uint256 _maxMultiplier,
        uint256 _minHoldingTime
    ) external pollExists(_pollId) onlyPollCreator(_pollId) {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.TIME_WEIGHTED) revert InvalidPollType();
        
        TimeWeightConfig storage config = pollTimeWeights[_pollId];
        config.baseMultiplier = _baseMultiplier;
        config.timeBonus = _timeBonus;
        config.maxMultiplier = _maxMultiplier;
        config.minHoldingTime = _minHoldingTime;
        
        emit TimeWeightConfigSet(_pollId, _baseMultiplier, _timeBonus, _maxMultiplier);
    }

    function trackTokenHolding(address _token) external {
        if (tokenFirstSeen[msg.sender][_token] == 0) {
            IERC20 token = IERC20(_token);
            if (token.balanceOf(msg.sender) > 0) {
                tokenFirstSeen[msg.sender][_token] = block.timestamp;
                emit TokenHoldingTracked(msg.sender, _token, block.timestamp);
            }
        }
    }

    function calculateTimeWeight(
        address _user,
        address _token,
        uint256 _pollId
    ) public view returns (uint256) {
        TimeWeightConfig memory config = pollTimeWeights[_pollId];
        if (config.baseMultiplier == 0) return 1e18; // Default 1x multiplier
        
        uint256 firstSeen = tokenFirstSeen[_user][_token];
        if (firstSeen == 0) return config.baseMultiplier;
        
        uint256 holdingTime = block.timestamp - firstSeen;
        if (holdingTime < config.minHoldingTime) return config.baseMultiplier;
        
        uint256 daysHeld = holdingTime / 1 days;
        uint256 timeMultiplier = config.baseMultiplier + (daysHeld * config.timeBonus);
        
        if (timeMultiplier > config.maxMultiplier) {
            timeMultiplier = config.maxMultiplier;
        }
        
        return timeMultiplier;
    }

    function voteTimeWeighted(uint256 _pollId, uint256 _optionIndex)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.TIME_WEIGHTED) revert InvalidPollType();
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        uint256 weight = 1;
        
        if (poll.requiresToken) {
            IERC20 token = IERC20(poll.tokenAddress);
            uint256 balance = token.balanceOf(msg.sender);
            if (balance < poll.minTokenBalance) revert InsufficientTokenBalance();
            
            // Calculate base token weight
            uint256 baseWeight = balance / 1e18;
            if (baseWeight == 0) baseWeight = 1;
            
            // Apply time multiplier
            uint256 timeMultiplier = calculateTimeWeight(msg.sender, poll.tokenAddress, _pollId);
            weight = (baseWeight * timeMultiplier) / 1e18;
            if (weight == 0) weight = 1;
        }

        poll.hasVoted[msg.sender] = true;
        poll.voterWeight[msg.sender] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    function getTimeWeightConfig(uint256 _pollId)
        external
        view
        pollExists(_pollId)
        returns (
            uint256 baseMultiplier,
            uint256 timeBonus,
            uint256 maxMultiplier,
            uint256 minHoldingTime
        )
    {
        TimeWeightConfig memory config = pollTimeWeights[_pollId];
        return (
            config.baseMultiplier,
            config.timeBonus,
            config.maxMultiplier,
            config.minHoldingTime
        );
    }

    function getUserTokenHoldingTime(address _user, address _token)
        external
        view
        returns (uint256 firstSeen, uint256 holdingTime)
    {
        firstSeen = tokenFirstSeen[_user][_token];
        if (firstSeen == 0) {
            holdingTime = 0;
        } else {
            holdingTime = block.timestamp - firstSeen;
        }
    }

    // Reputation System Functions
    function _initializeReputationSystem() internal {
        reputationConfig = ReputationConfig({
            votePoints: 10, // 10 points per vote
            createPoints: 50, // 50 points per poll created
            successPoints: 100, // 100 points per successful poll
            decayRate: 1e16, // 1% decay per day
            minActivityTime: 1 hours, // Minimum 1 hour between activities
            maxReputation: 10000 // Maximum 10,000 reputation points
        });
    }

    function updateReputationConfig(
        uint256 _votePoints,
        uint256 _createPoints,
        uint256 _successPoints,
        uint256 _decayRate,
        uint256 _minActivityTime,
        uint256 _maxReputation
    ) external onlyOwner {
        reputationConfig.votePoints = _votePoints;
        reputationConfig.createPoints = _createPoints;
        reputationConfig.successPoints = _successPoints;
        reputationConfig.decayRate = _decayRate;
        reputationConfig.minActivityTime = _minActivityTime;
        reputationConfig.maxReputation = _maxReputation;
        
        emit ReputationConfigUpdated(_votePoints, _createPoints, _successPoints);
    }

    function _updateUserReputation(address _user, bool _isVote, bool _isPollCreation) internal {
        UserReputation storage rep = userReputations[_user];
        
        // Apply time decay if enough time has passed
        if (rep.lastActivityTime > 0) {
            uint256 timePassed = block.timestamp - rep.lastActivityTime;
            uint256 daysPassed = timePassed / 1 days;
            
            if (daysPassed > 0) {
                uint256 decayAmount = (rep.reputationScore * reputationConfig.decayRate * daysPassed) / 1e18;
                if (decayAmount > rep.reputationScore) {
                    rep.reputationScore = 0;
                } else {
                    rep.reputationScore -= decayAmount;
                }
            }
        }
        
        // Add points for activity
        if (_isVote) {
            rep.totalVotes++;
            rep.reputationScore += reputationConfig.votePoints;
        }
        
        if (_isPollCreation) {
            rep.pollsCreated++;
            rep.reputationScore += reputationConfig.createPoints;
        }
        
        // Cap reputation at maximum
        if (rep.reputationScore > reputationConfig.maxReputation) {
            rep.reputationScore = reputationConfig.maxReputation;
        }
        
        rep.lastActivityTime = block.timestamp;
        rep.isActive = true;
        
        emit ReputationUpdated(_user, rep.reputationScore, rep.totalVotes, rep.pollsCreated);
    }

    function calculateReputationVotingWeight(address _user) public view returns (uint256) {
        UserReputation memory rep = userReputations[_user];
        if (rep.reputationScore == 0) return 1e18; // Base weight 1x
        
        // Reputation weight: 1x + (reputation / 1000)
        // Max reputation 10,000 = 11x weight
        uint256 reputationMultiplier = 1e18 + ((rep.reputationScore * 1e18) / 1000);
        return reputationMultiplier;
    }

    function voteReputationBased(uint256 _pollId, uint256 _optionIndex)
        external
        nonReentrant
        pollExists(_pollId)
        pollActive(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.pollType != PollType.REPUTATION_BASED) revert InvalidPollType();
        if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
        if (_optionIndex >= poll.options.length) revert InvalidOption();

        // Calculate reputation-based weight
        uint256 reputationWeight = calculateReputationVotingWeight(msg.sender);
        uint256 weight = 1;
        
        if (poll.requiresToken) {
            IERC20 token = IERC20(poll.tokenAddress);
            uint256 balance = token.balanceOf(msg.sender);
            if (balance < poll.minTokenBalance) revert InsufficientTokenBalance();
            
            // Base token weight
            uint256 baseWeight = balance / 1e18;
            if (baseWeight == 0) baseWeight = 1;
            
            // Apply reputation multiplier
            weight = (baseWeight * reputationWeight) / 1e18;
            if (weight == 0) weight = 1;
        } else {
            // Pure reputation-based weight
            weight = reputationWeight / 1e18;
            if (weight == 0) weight = 1;
        }

        poll.hasVoted[msg.sender] = true;
        poll.voterWeight[msg.sender] = weight;
        poll.votes[_optionIndex] += weight;
        poll.totalVotes++;
        poll.totalWeight += weight;

        userVotedPolls[msg.sender].push(_pollId);
        analytics.totalVotesCast++;

        // Update user reputation for voting
        _updateUserReputation(msg.sender, true, false);

        emit VoteCast(_pollId, msg.sender, _optionIndex, weight);
    }

    function getUserReputation(address _user)
        external
        view
        returns (
            uint256 totalVotes,
            uint256 pollsCreated,
            uint256 successfulPolls,
            uint256 reputationScore,
            uint256 lastActivityTime,
            bool isActive
        )
    {
        UserReputation memory rep = userReputations[_user];
        return (
            rep.totalVotes,
            rep.pollsCreated,
            rep.successfulPolls,
            rep.reputationScore,
            rep.lastActivityTime,
            rep.isActive
        );
    }

    function getReputationConfig()
        external
        view
        returns (
            uint256 votePoints,
            uint256 createPoints,
            uint256 successPoints,
            uint256 decayRate,
            uint256 minActivityTime,
            uint256 maxReputation
        )
    {
        return (
            reputationConfig.votePoints,
            reputationConfig.createPoints,
            reputationConfig.successPoints,
            reputationConfig.decayRate,
            reputationConfig.minActivityTime,
            reputationConfig.maxReputation
        );
    }

    // Reward System Functions
    function _initializeRewardSystem() internal {
        rewardPool = RewardPool({
            totalRewards: 0,
            creatorRewardPercentage: 30, // 30% for creators
            voterRewardPercentage: 70, // 70% for voters
            minParticipationForReward: 5, // Minimum 5 votes
            isActive: false // Initially inactive
        });
    }

    function fundRewardPool() external payable onlyOwner {
        rewardPool.totalRewards += msg.value;
        emit RewardPoolFunded(msg.value);
    }

    function updateRewardPool(
        uint256 _creatorPercentage,
        uint256 _voterPercentage,
        uint256 _minParticipation,
        bool _isActive
    ) external onlyOwner {
        if (_creatorPercentage + _voterPercentage != 100) revert InvalidAddress(); // Reusing error
        
        rewardPool.creatorRewardPercentage = _creatorPercentage;
        rewardPool.voterRewardPercentage = _voterPercentage;
        rewardPool.minParticipationForReward = _minParticipation;
        rewardPool.isActive = _isActive;
        
        emit RewardPoolUpdated(rewardPool.totalRewards, _creatorPercentage, _voterPercentage);
    }

    function distributeRewards(uint256 _pollId) external pollExists(_pollId) {
        Poll storage poll = polls[_pollId];
        if (poll.status != PollStatus.CLOSED && poll.status != PollStatus.EXPIRED) {
            revert PollNotActive();
        }
        if (!rewardPool.isActive) return;
        if (poll.totalVotes < rewardPool.minParticipationForReward) return;
        if (pollRewardAllocations[_pollId] > 0) return; // Already distributed
        
        // Calculate reward amount based on poll participation
        uint256 baseReward = 0.01 ether; // Base reward per poll
        uint256 participationBonus = (poll.totalVotes * 0.001 ether); // Bonus per vote
        uint256 totalPollReward = baseReward + participationBonus;
        
        if (totalPollReward > rewardPool.totalRewards) {
            totalPollReward = rewardPool.totalRewards;
        }
        
        if (totalPollReward == 0) return;
        
        // Calculate creator and voter rewards
        uint256 creatorReward = (totalPollReward * rewardPool.creatorRewardPercentage) / 100;
        uint256 voterReward = totalPollReward - creatorReward;
        
        // Distribute creator reward
        UserRewards storage creatorRewards = userRewards[poll.creator];
        creatorRewards.pendingRewards += creatorReward;
        creatorRewards.totalEarned += creatorReward;
        creatorRewards.pollsRewarded++;
        
        // Distribute voter rewards (simplified - equal distribution)
        if (poll.totalVotes > 0) {
            uint256 rewardPerVote = voterReward / poll.totalVotes;
            // In practice, you'd need to iterate through all voters
            // This is a simplified version
        }
        
        // Update pool and allocations
        rewardPool.totalRewards -= totalPollReward;
        pollRewardAllocations[_pollId] = totalPollReward;
        
        emit RewardsDistributed(_pollId, totalPollReward, creatorReward, voterReward);
    }

    function claimRewards() external nonReentrant {
        UserRewards storage rewards = userRewards[msg.sender];
        uint256 claimAmount = rewards.pendingRewards;
        
        if (claimAmount == 0) revert InvalidAddress(); // Reusing error for no rewards
        
        rewards.pendingRewards = 0;
        rewards.lastClaimTime = block.timestamp;
        
        payable(msg.sender).transfer(claimAmount);
        emit RewardClaimed(msg.sender, claimAmount);
    }

    function getUserRewards(address _user)
        external
        view
        returns (
            uint256 totalEarned,
            uint256 pendingRewards,
            uint256 lastClaimTime,
            uint256 pollsRewarded
        )
    {
        UserRewards memory rewards = userRewards[_user];
        return (
            rewards.totalEarned,
            rewards.pendingRewards,
            rewards.lastClaimTime,
            rewards.pollsRewarded
        );
    }

    function getRewardPoolInfo()
        external
        view
        returns (
            uint256 totalRewards,
            uint256 creatorPercentage,
            uint256 voterPercentage,
            uint256 minParticipation,
            bool isActive
        )
    {
        return (
            rewardPool.totalRewards,
            rewardPool.creatorRewardPercentage,
            rewardPool.voterRewardPercentage,
            rewardPool.minParticipationForReward,
            rewardPool.isActive
        );
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

    function archivePoll(uint256 _pollId) 
        external 
        pollExists(_pollId) 
        onlyPollCreator(_pollId)
    {
        Poll storage poll = polls[_pollId];
        if (poll.status != PollStatus.CLOSED && poll.status != PollStatus.EXPIRED) {
            revert PollNotActive();
        }
        if (block.timestamp < poll.endTime + archiveDelay) {
            revert PollTooRecentToArchive();
        }
        
        poll.isArchived = true;
        poll.archivedAt = block.timestamp;
        poll.status = PollStatus.ARCHIVED;
        
        emit PollArchived(_pollId);
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
            tags: poll.tags,
            templateId: poll.templateId,
            isArchived: poll.isArchived,
            archivedAt: poll.archivedAt
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

    // Template functions
    function createPollTemplate(
        string memory _name,
        string memory _description,
        PollType _pollType,
        PollCategory _category,
        uint256 _defaultDuration,
        uint256 _defaultMinParticipation,
        bool _requiresToken,
        uint256 _defaultMinTokenBalance,
        string[] memory _defaultTags
    ) external onlyOwner returns (uint256) {
        uint256 templateId = templateCount++;
        
        PollTemplate storage template = pollTemplates[templateId];
        template.id = templateId;
        template.name = _name;
        template.description = _description;
        template.pollType = _pollType;
        template.category = _category;
        template.defaultDuration = _defaultDuration;
        template.defaultMinParticipation = _defaultMinParticipation;
        template.requiresToken = _requiresToken;
        template.defaultMinTokenBalance = _defaultMinTokenBalance;
        template.defaultTags = _defaultTags;
        template.isActive = true;
        
        emit PollTemplateCreated(templateId, _name);
        return templateId;
    }

    function getPollTemplate(uint256 _templateId) 
        external 
        view 
        templateExists(_templateId) 
        returns (
            uint256 id,
            string memory name,
            string memory description,
            PollType pollType,
            PollCategory category,
            uint256 defaultDuration,
            uint256 defaultMinParticipation,
            bool requiresToken,
            uint256 defaultMinTokenBalance,
            string[] memory defaultTags,
            bool isActive
        ) 
    {
        PollTemplate storage template = pollTemplates[_templateId];
        return (
            template.id,
            template.name,
            template.description,
            template.pollType,
            template.category,
            template.defaultDuration,
            template.defaultMinParticipation,
            template.requiresToken,
            template.defaultMinTokenBalance,
            template.defaultTags,
            template.isActive
        );
    }

    function toggleTemplate(uint256 _templateId) external onlyOwner templateExists(_templateId) {
        pollTemplates[_templateId].isActive = !pollTemplates[_templateId].isActive;
    }

    // Enhanced delegation functions
    function setDelegate(address _delegate, DelegationType _delegationType) external {
        if (_delegate == msg.sender) revert CannotDelegateToSelf();
        if (_delegate == address(0)) revert InvalidAddress();
        
        address currentDelegate = delegates[msg.sender];
        if (currentDelegate != address(0)) {
            _removeDelegator(currentDelegate, msg.sender);
            emit DelegateRemoved(msg.sender, currentDelegate);
        }
        
        delegates[msg.sender] = _delegate;
        delegators[_delegate].push(msg.sender);
        
        DelegationInfo storage info = delegationInfo[msg.sender];
        info.delegate = _delegate;
        info.delegationType = _delegationType;
        info.delegatedAt = block.timestamp;
        info.isActive = true;
        
        emit DelegateSet(msg.sender, _delegate);
    }
    
    function removeDelegate() external {
        address currentDelegate = delegates[msg.sender];
        if (currentDelegate == address(0)) revert NoDelegateSet();
        
        _removeDelegator(currentDelegate, msg.sender);
        delegates[msg.sender] = address(0);
        
        DelegationInfo storage info = delegationInfo[msg.sender];
        info.isActive = false;
        
        emit DelegateRemoved(msg.sender, currentDelegate);
    }

    function getDelegationInfo(address _user) 
        external 
        view 
        returns (
            address delegate,
            DelegationType delegationType,
            uint256 delegatedAt,
            uint256 totalDelegatedWeight,
            bool isActive
        ) 
    {
        DelegationInfo storage info = delegationInfo[_user];
        return (
            info.delegate,
            info.delegationType,
            info.delegatedAt,
            info.totalDelegatedWeight,
            info.isActive
        );
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

        // Update delegation analytics
        delegationInfo[_delegator].totalDelegatedWeight += weight;

        emit VoteCast(_pollId, _delegator, _optionIndex, weight);
    }
    
    function getDelegators(address _delegate) external view returns (address[] memory) {
        return delegators[_delegate];
    }
    
    function getDelegate(address _user) external view returns (address) {
        return delegates[_user];
    }

    // Analytics functions
    function getAnalytics() 
        external 
        view 
        returns (
            uint256 totalPollsCreated,
            uint256 totalVotesCast,
            uint256 totalUniqueVoters,
            uint256 averageParticipationRate
        ) 
    {
        return (
            analytics.totalPollsCreated,
            analytics.totalVotesCast,
            analytics.totalUniqueVoters,
            analytics.averageParticipationRate
        );
    }

    function getCategoryStats(PollCategory _category) external view returns (uint256) {
        return analytics.pollsByCategory[_category];
    }

    function getTypeStats(PollType _pollType) external view returns (uint256) {
        return analytics.pollsByType[_pollType];
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

    function setArchiveDelay(uint256 _delay) external onlyOwner {
        archiveDelay = _delay;
    }

    function setDefaultTokenAddress(address _tokenAddress) external onlyOwner {
        defaultTokenAddress = _tokenAddress;
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

    function _createDefaultTemplates() internal {
        // Governance template
        string[] memory govTags = new string[](2);
        govTags[0] = "governance";
        govTags[1] = "dao";
        
        _createPollTemplateInternal(
            "Governance Proposal",
            "Standard template for governance proposals",
            PollType.WEIGHTED,
            PollCategory.GOVERNANCE,
            14 days,
            10,
            true,
            1000 * 1e18,
            govTags
        );

        // Community template
        string[] memory communityTags = new string[](2);
        communityTags[0] = "community";
        communityTags[1] = "events";
        
        _createPollTemplateInternal(
            "Community Poll",
            "Template for community engagement polls",
            PollType.STANDARD,
            PollCategory.COMMUNITY,
            7 days,
            5,
            false,
            0,
            communityTags
        );

        // Technical template
        string[] memory techTags = new string[](2);
        techTags[0] = "technical";
        techTags[1] = "development";
        
        _createPollTemplateInternal(
            "Technical Decision",
            "Template for technical decisions and proposals",
            PollType.QUADRATIC,
            PollCategory.TECHNICAL,
            21 days,
            15,
            true,
            500 * 1e18,
            techTags
        );
    }

    function _createPollTemplateInternal(
        string memory _name,
        string memory _description,
        PollType _pollType,
        PollCategory _category,
        uint256 _defaultDuration,
        uint256 _defaultMinParticipation,
        bool _requiresToken,
        uint256 _defaultMinTokenBalance,
        string[] memory _defaultTags
    ) internal returns (uint256) {
        uint256 templateId = templateCount++;
        
        PollTemplate storage template = pollTemplates[templateId];
        template.id = templateId;
        template.name = _name;
        template.description = _description;
        template.pollType = _pollType;
        template.category = _category;
        template.defaultDuration = _defaultDuration;
        template.defaultMinParticipation = _defaultMinParticipation;
        template.requiresToken = _requiresToken;
        template.defaultMinTokenBalance = _defaultMinTokenBalance;
        template.defaultTags = _defaultTags;
        template.isActive = true;
        
        emit PollTemplateCreated(templateId, _name);
        return templateId;
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
            // Direct vote logic to avoid reentrancy
            uint256 pollId = _pollIds[i];
            uint256 optionIndex = _optionIndices[i];
            
            Poll storage poll = polls[pollId];
            
            if (poll.status != PollStatus.ACTIVE) revert PollNotActive();
            if (block.timestamp > poll.endTime) {
                poll.status = PollStatus.EXPIRED;
                emit PollStatusChanged(pollId, PollStatus.EXPIRED);
                revert PollNotActive();
            }
            
            if (poll.hasVoted[msg.sender]) revert AlreadyVoted();
            if (optionIndex >= poll.options.length) revert InvalidOption();

            uint256 weight = 1;

            // Handle different voting types
            if (poll.pollType == PollType.WEIGHTED || poll.pollType == PollType.QUADRATIC) {
                if (poll.requiresToken) {
                    IERC20 token = IERC20(poll.tokenAddress);
                    uint256 balance = token.balanceOf(msg.sender);
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

            poll.hasVoted[msg.sender] = true;
            poll.voterWeight[msg.sender] = weight;
            poll.votes[optionIndex] += weight;
            poll.totalVotes++;
            poll.totalWeight += weight;

            userVotedPolls[msg.sender].push(pollId);

            // Update analytics
            analytics.totalVotesCast++;

            emit VoteCast(pollId, msg.sender, optionIndex, weight);
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

    // Frontend helper functions
    function getPollsForFrontend(
        uint256 _offset,
        uint256 _limit,
        PollStatus _status,
        PollCategory _category
    ) external view returns (uint256[] memory pollIds, PollView[] memory pollViews) {
        uint256[] memory allPolls = this.getFilteredPolls(_status, _category, false);
        
        uint256 start = _offset;
        uint256 end = start + _limit;
        if (end > allPolls.length) end = allPolls.length;
        
        uint256 count = end - start;
        pollIds = new uint256[](count);
        pollViews = new PollView[](count);
        
        for (uint256 i = 0; i < count; i++) {
            pollIds[i] = allPolls[start + i];
            pollViews[i] = this.getPoll(pollIds[i]);
        }
    }

    function getPollSummary(uint256 _pollId) 
        external 
        view 
        pollExists(_pollId) 
        returns (
            string memory question,
            uint256 totalVotes,
            uint256 totalWeight,
            PollStatus status,
            bool isActive
        ) 
    {
        Poll storage poll = polls[_pollId];
        return (
            poll.question,
            poll.totalVotes,
            poll.totalWeight,
            poll.status,
            poll.status == PollStatus.ACTIVE && block.timestamp <= poll.endTime
        );
    }
} 