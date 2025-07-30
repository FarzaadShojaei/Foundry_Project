// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract GovernanceToken is ERC20, ERC20Permit, Ownable {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 1e18; // 1 billion tokens
    uint256 public constant INITIAL_MINT = 100_000_000 * 1e18; // 100 million tokens
    
    mapping(address => bool) public minters;
    mapping(address => uint256) public votingPower;
    
    event MinterAdded(address indexed minter);
    event MinterRemoved(address indexed minter);
    event VotingPowerUpdated(address indexed user, uint256 newPower);

    constructor() 
        ERC20("PollGovernance", "POLL") 
        ERC20Permit("PollGovernance")
        Ownable(msg.sender)
    {
        _mint(msg.sender, INITIAL_MINT);
        votingPower[msg.sender] = INITIAL_MINT;
    }

    modifier onlyMinter() {
        require(minters[msg.sender] || msg.sender == owner(), "Not authorized to mint");
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds max supply");
        _mint(to, amount);
        _updateVotingPower(to);
    }

    function addMinter(address minter) external onlyOwner {
        minters[minter] = true;
        emit MinterAdded(minter);
    }

    function removeMinter(address minter) external onlyOwner {
        minters[minter] = false;
        emit MinterRemoved(minter);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        _updateVotingPower(msg.sender);
    }

    function getVotingPower(address user) external view returns (uint256) {
        return votingPower[user];
    }

    function _updateVotingPower(address user) internal {
        uint256 newPower = balanceOf(user);
        votingPower[user] = newPower;
        emit VotingPowerUpdated(user, newPower);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        super._update(from, to, value);
        
        if (from != address(0)) {
            _updateVotingPower(from);
        }
        if (to != address(0)) {
            _updateVotingPower(to);
        }
    }

    // Airdrop function for initial distribution
    function airdrop(address[] calldata recipients, uint256[] calldata amounts) 
        external 
        onlyOwner 
    {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(totalSupply() + amounts[i] <= MAX_SUPPLY, "Exceeds max supply");
            _mint(recipients[i], amounts[i]);
            _updateVotingPower(recipients[i]);
        }
    }

    // Batch transfer for gas efficiency
    function batchTransfer(address[] calldata recipients, uint256[] calldata amounts) 
        external 
    {
        require(recipients.length == amounts.length, "Array length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            transfer(recipients[i], amounts[i]);
        }
    }
} 