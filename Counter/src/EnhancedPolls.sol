// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EnhancedPolls is Ownable, ReentrancyGuard {
    // Enums
    enum PollType { STANDARD, WEIGHTED, QUADRATIC }
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