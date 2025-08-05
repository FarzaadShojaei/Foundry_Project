use ethers::prelude::*;
use std::sync::Arc;
use anyhow::Result;
use clap::{Parser, Subcommand};
use colored::*;
use chrono::DateTime;
use indicatif::{ProgressBar, ProgressStyle};
use tabled::{Table, Tabled};
use serde::{Deserialize, Serialize};

// Contract ABI for EnhancedPolls
abigen!(
    EnhancedPolls,
    r#"[
        function createPoll(string memory _question, string[] memory _options, uint256 _durationInSeconds, uint8 _pollType, uint8 _category, uint256 _minParticipation, address _tokenAddress, uint256 _minTokenBalance, string memory _description, string[] memory _tags) external payable returns (uint256)
        function vote(uint256 _pollId, uint256 _optionIndex) external
        function voteAsDelegate(uint256 _pollId, uint256 _optionIndex, address _delegator) external
        function closePoll(uint256 _pollId) external
        function extendPoll(uint256 _pollId, uint256 _additionalTime) external
        function setDelegate(address _delegate) external
        function removeDelegate() external
        function getPoll(uint256 _pollId) external view returns (tuple(uint256 id, string question, string[] options, address creator, uint256 createdAt, uint256 endTime, uint8 status, uint8 pollType, uint8 category, uint256 minParticipation, uint256 totalVotes, uint256 totalWeight, string description, string[] tags))
        function getPollResults(uint256 _pollId) external view returns (uint256[] memory votes, uint256 totalVotes, uint256 totalWeight)
        function getPollsByCategory(uint8 _category) external view returns (uint256[] memory)
        function getPollsByTag(string memory _tag) external view returns (uint256[] memory)
        function getFilteredPolls(uint8 _status, uint8 _category, bool _activeOnly) external view returns (uint256[] memory)
        function hasUserVoted(uint256 _pollId, address _user) external view returns (bool)
        function getUserCreatedPolls(address _user) external view returns (uint256[] memory)
        function getUserVotedPolls(address _user) external view returns (uint256[] memory)
        function getUserStats(address _user) external view returns (uint256 pollsCreated, uint256 pollsVoted, uint256 totalVotingWeight)
        function getDelegators(address _delegate) external view returns (address[] memory)
        function getDelegate(address _user) external view returns (address)
        function isPollActive(uint256 _pollId) external view returns (bool)
        function getTotalVotes(uint256 _pollId) external view returns (uint256)
        function getActivePollsCount() external view returns (uint256)
        function pollCount() external view returns (uint256)
        event PollCreated(uint256 indexed pollId, address indexed creator, string question, uint8 pollType, uint8 category, uint256 endTime, string[] tags)
        event VoteCast(uint256 indexed pollId, address indexed voter, uint256 optionIndex, uint256 weight)
        event PollStatusChanged(uint256 indexed pollId, uint8 newStatus)
        event DelegateSet(address indexed delegator, address indexed delegate)
        event DelegateRemoved(address indexed delegator, address indexed delegate)
    ]"#
);

// GovernanceToken ABI for token operations
abigen!(
    GovernanceToken,
    r#"[
        function balanceOf(address account) external view returns (uint256)
        function transfer(address to, uint256 amount) external returns (bool)
        function approve(address spender, uint256 amount) external returns (bool)
        function totalSupply() external view returns (uint256)
        function getVotingPower(address user) external view returns (uint256)
        function name() external view returns (string memory)
        function symbol() external view returns (string memory)
        function decimals() external view returns (uint8)
    ]"#
);

#[derive(Debug, Serialize, Deserialize, Tabled)]
struct PollExport {
    id: u64,
    question: String,
    creator: String,
    created_at: String,
    end_time: String,
    is_active: bool,
    total_votes: u64,
    #[tabled(display_with = "display_vec_string")]
    options: Vec<String>,
    #[tabled(display_with = "display_vec_u64")]
    votes: Vec<u64>,
}

fn display_vec_string(vec: &Vec<String>) -> String {
    vec.join(", ")
}

fn display_vec_u64(vec: &Vec<u64>) -> String {
    vec.iter().map(|v| v.to_string()).collect::<Vec<_>>().join(", ")
}

#[derive(Debug, Serialize, Deserialize)]
struct PollAnalytics {
    poll_id: u64,
    question: String,
    total_votes: u64,
    participation_rate: f64,
    leading_option: String,
    margin: f64,
    time_remaining: Option<String>,
    created_at: String,
    options_detail: Vec<OptionDetail>,
}

#[derive(Debug, Serialize, Deserialize)]
struct OptionDetail {
    index: usize,
    option: String,
    votes: u64,
    percentage: f64,
}

#[derive(Parser)]
#[command(name = "polling-cli")]
#[command(about = "A CLI for interacting with the DecentralizedPolls smart contract")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Create a new enhanced poll
    Create {
        /// Question for the poll
        #[arg(short, long)]
        question: String,
        /// Poll options (comma-separated)
        #[arg(short, long)]
        options: String,
        /// Duration in hours (default: 168 = 7 days)
        #[arg(short, long, default_value = "168")]
        duration: u64,
        /// Poll type: standard, weighted, quadratic
        #[arg(short = 't', long, default_value = "standard")]
        poll_type: String,
        /// Category: general, governance, technical, community, finance
        #[arg(short = 'c', long, default_value = "general")]
        category: String,
        /// Minimum participation required
        #[arg(short = 'm', long, default_value = "0")]
        min_participation: u64,
        /// Token address for weighted/quadratic voting (optional)
        #[arg(long)]
        token_address: Option<String>,
        /// Minimum token balance required to vote
        #[arg(long, default_value = "0")]
        min_token_balance: u64,
        /// Extended description of the poll
        #[arg(long)]
        description: Option<String>,
        /// Tags for the poll (comma-separated)
        #[arg(long)]
        tags: Option<String>,
    },
    /// Vote on a poll
    Vote {
        /// Poll ID to vote on
        #[arg(short, long)]
        poll_id: u64,
        /// Option index to vote for
        #[arg(short, long)]
        option: u64,
    },
    /// Vote as a delegate for someone else
    VoteDelegate {
        /// Poll ID to vote on
        #[arg(short, long)]
        poll_id: u64,
        /// Option index to vote for
        #[arg(short, long)]
        option: u64,
        /// Address of the person you're voting for
        #[arg(short, long)]
        delegator: String,
    },
    /// Set a delegate for your votes
    SetDelegate {
        /// Address of the delegate
        #[arg(short, long)]
        delegate: String,
    },
    /// Remove your current delegate
    RemoveDelegate,
    /// View poll details
    View {
        /// Poll ID to view
        #[arg(short, long)]
        poll_id: u64,
    },
    /// List polls with filtering options
    List {
        /// Filter by category
        #[arg(short, long)]
        category: Option<String>,
        /// Filter by tag
        #[arg(short, long)]
        tag: Option<String>,
        /// Show only active polls
        #[arg(long)]
        active_only: bool,
    },
    /// View poll results
    Results {
        /// Poll ID to get results for
        #[arg(short, long)]
        poll_id: u64,
    },
    /// Close a poll (creator only)
    Close {
        /// Poll ID to close
        #[arg(short, long)]
        poll_id: u64,
    },
    /// Extend a poll duration (creator only)
    Extend {
        /// Poll ID to extend
        #[arg(short, long)]
        poll_id: u64,
        /// Additional hours to add
        #[arg(short, long)]
        hours: u64,
    },
    /// View user's created polls
    MyPolls,
    /// View polls user has voted on
    MyVotes,
    /// View user statistics
    MyStats,
    /// View delegation information
    Delegation {
        /// Address to check delegation for (optional, defaults to your address)
        #[arg(short, long)]
        address: Option<String>,
    },
    /// Check token balance
    TokenBalance {
        /// Token contract address (optional, uses governance token if not specified)
        #[arg(short, long)]
        token: Option<String>,
        /// Address to check (optional, defaults to your address)
        #[arg(short, long)]
        address: Option<String>,
    },
    /// Export poll data to various formats
    Export {
        /// Poll ID to export
        #[arg(short, long)]
        poll_id: u64,
        /// Export format (json, csv, table)
        #[arg(short, long, default_value = "json")]
        format: String,
        /// Output file path
        #[arg(short, long)]
        output: Option<String>,
    },
    /// Generate comprehensive poll analytics
    Analytics {
        /// Poll ID for analytics (optional, shows all if not provided)
        #[arg(short, long)]
        poll_id: Option<u64>,
    },
}

pub struct PollManager {
    contract: EnhancedPolls<SignerMiddleware<Provider<Http>, LocalWallet>>,
    governance_token: Option<GovernanceToken<SignerMiddleware<Provider<Http>, LocalWallet>>>,
    signer: Arc<SignerMiddleware<Provider<Http>, LocalWallet>>,
}

// Helper functions for enum conversions
fn poll_type_to_u8(poll_type: &str) -> Result<u8> {
    match poll_type.to_lowercase().as_str() {
        "standard" => Ok(0),
        "weighted" => Ok(1),
        "quadratic" => Ok(2),
        _ => anyhow::bail!("Invalid poll type. Use: standard, weighted, quadratic"),
    }
}

fn category_to_u8(category: &str) -> Result<u8> {
    match category.to_lowercase().as_str() {
        "general" => Ok(0),
        "governance" => Ok(1),
        "technical" => Ok(2),
        "community" => Ok(3),
        "finance" => Ok(4),
        _ => anyhow::bail!("Invalid category. Use: general, governance, technical, community, finance"),
    }
}

fn u8_to_poll_type(poll_type: u8) -> &'static str {
    match poll_type {
        0 => "Standard",
        1 => "Weighted",
        2 => "Quadratic",
        _ => "Unknown",
    }
}

fn u8_to_category(category: u8) -> &'static str {
    match category {
        0 => "General",
        1 => "Governance",
        2 => "Technical",
        3 => "Community",
        4 => "Finance",
        _ => "Unknown",
    }
}

fn u8_to_status(status: u8) -> &'static str {
    match status {
        0 => "Active",
        1 => "Closed",
        2 => "Expired",
        3 => "Cancelled",
        _ => "Unknown",
    }
}

impl PollManager {
    pub async fn new(rpc_url: &str, private_key: &str, contract_address: &str) -> Result<Self> {
        // Setup provider and wallet
        let provider = Provider::<Http>::try_from(rpc_url)?;
        let wallet: LocalWallet = private_key.parse()?;
        let chain_id = provider.get_chainid().await?;
        let wallet = wallet.with_chain_id(chain_id.as_u64());
        
        // Create signer middleware
        let signer = Arc::new(SignerMiddleware::new(provider, wallet));
        
        // Create contract instance
        let contract_address: Address = contract_address.parse()?;
        let contract = EnhancedPolls::new(contract_address, signer.clone());

        Ok(Self { 
            contract, 
            governance_token: None,
            signer 
        })
    }

    pub async fn set_governance_token(&mut self, token_address: &str) -> Result<()> {
        let token_address: Address = token_address.parse()?;
        let governance_token = GovernanceToken::new(token_address, self.signer.clone());
        self.governance_token = Some(governance_token);
        Ok(())
    }

    pub async fn create_enhanced_poll(
        &self,
        question: String,
        options: Vec<String>,
        duration_hours: u64,
        poll_type: &str,
        category: &str,
        min_participation: u64,
        token_address: Option<String>,
        min_token_balance: u64,
        description: Option<String>,
        tags: Option<String>,
    ) -> Result<U256> {
        println!("{}", "🚀 Creating enhanced poll...".cyan().bold());
        println!("{} {}", "Question:".yellow().bold(), question);
        println!("{} {:?}", "Options:".yellow().bold(), options);
        println!("{} {} hours", "Duration:".yellow().bold(), duration_hours);
        println!("{} {}", "Type:".yellow().bold(), poll_type);
        println!("{} {}", "Category:".yellow().bold(), category);

        // Convert parameters
        let poll_type_u8 = poll_type_to_u8(poll_type)?;
        let category_u8 = category_to_u8(category)?;
        let duration_seconds = duration_hours * 3600; // Convert hours to seconds
        
        let token_addr = if let Some(addr) = token_address {
            addr.parse::<Address>()?
        } else {
            Address::zero()
        };

        let desc = description.unwrap_or_else(|| "No description provided".to_string());
        let tags_vec: Vec<String> = if let Some(tags_str) = tags {
            tags_str.split(',').map(|s| s.trim().to_string()).collect()
        } else {
            vec![]
        };

        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner().template("{spinner:.green} {msg}").unwrap());
        pb.set_message("Submitting transaction...");
        pb.enable_steady_tick(std::time::Duration::from_millis(100));

        let contract_call = self.contract.create_poll(
            question,
            options,
            U256::from(duration_seconds),
            poll_type_u8,
            category_u8,
            U256::from(min_participation),
            token_addr,
            U256::from(min_token_balance) * U256::from(10).pow(U256::from(18)), // Convert to wei
            desc,
            tags_vec,
        );

        let tx = contract_call.send().await?;
        let receipt = tx.await?;
        pb.finish_and_clear();
        
        // Parse logs to get poll ID
        if let Some(receipt) = receipt {
            for log in receipt.logs {
                if log.topics.len() > 1 {
                    let poll_id_u256 = U256::from(log.topics[1].as_bytes());
                    println!("{}", "✅ Enhanced poll created successfully!".green().bold());
                    println!("{} {}", "Poll ID:".cyan().bold(), poll_id_u256.to_string().yellow());
                    println!("{} {}", "Type:".cyan().bold(), u8_to_poll_type(poll_type_u8).green());
                    println!("{} {}", "Category:".cyan().bold(), u8_to_category(category_u8).green());
                    if !tags_vec.is_empty() {
                        println!("{} {:?}", "Tags:".cyan().bold(), tags_vec);
                    }
                    println!("{} {:?}", "Transaction hash:".cyan().bold(), receipt.transaction_hash);
                    return Ok(poll_id_u256);
                }
            }
        }

        anyhow::bail!("Failed to get poll ID from transaction receipt");
    }

    pub async fn vote(&self, poll_id: u64, option_index: u64) -> Result<()> {
        let poll_id_str = poll_id.to_string();
        let option_str = option_index.to_string();
        println!("{} {} {} {}", "🗳️ Voting on poll".cyan().bold(), poll_id_str.yellow(), "with option".cyan().bold(), option_str.yellow());

        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner().template("{spinner:.green} {msg}").unwrap());
        let message = "Submitting vote...";
        pb.set_message(message);
        pb.enable_steady_tick(std::time::Duration::from_millis(100));

        let contract_call = self.contract.vote(U256::from(poll_id), U256::from(option_index));
        let tx = contract_call.send().await?;

        let receipt = tx.await?;
        pb.finish_and_clear();
        
        if let Some(receipt) = receipt {
            println!("{}", "✅ Vote cast successfully!".green().bold());
            println!("{} {:?}", "Transaction hash:".cyan().bold(), receipt.transaction_hash);
        }

        Ok(())
    }

    pub async fn view_poll(&self, poll_id: u64) -> Result<()> {
        let poll_data = self.contract
            .get_poll(U256::from(poll_id))
            .call()
            .await?;

        println!("\n📊 Poll Details:");
        println!("ID: {}", poll_data.0);
        println!("Question: {}", poll_data.1);
        println!("Options:");
        for (i, option) in poll_data.2.iter().enumerate() {
            println!("  {}: {}", i, option);
        }
        println!("Creator: {:?}", poll_data.3);
        println!("Created: {}", poll_data.4);
        println!("End Time: {}", poll_data.5);
        println!("Active: {}", poll_data.6);

        // Get results
        let results = self.contract
            .get_poll_results(U256::from(poll_id))
            .call()
            .await?;

        let total_votes = self.contract
            .get_total_votes(U256::from(poll_id))
            .call()
            .await?;

        println!("\n📈 Current Results:");
        for (i, votes) in results.iter().enumerate() {
            let percentage = if total_votes > U256::zero() {
                (votes.as_u64() * 100) / total_votes.as_u64()
            } else {
                0
            };
            println!("  {}: {} ({} votes, {}%)", poll_data.2[i], votes, votes, percentage);
        }
        println!("Total votes: {}", total_votes);

        Ok(())
    }

    pub async fn list_polls(&self) -> Result<()> {
        let poll_count = self.contract.poll_count().call().await?;
        
        println!("\n📋 All Polls:");
        println!("Total polls: {}", poll_count);
        
        for i in 0..poll_count.as_u64() {
            let poll_data = self.contract
                .get_poll(U256::from(i))
                .call()
                .await?;
            
            let is_active = self.contract
                .is_poll_active(U256::from(i))
                .call()
                .await?;

            let status = if is_active { "🟢 Active".green() } else { "🔴 Closed".red() };
            
            println!("\nPoll #{}: {}", i, poll_data.1);
            println!("  Status: {}", status);
            println!("  Options: {}", poll_data.2.len());
            println!("  Creator: {:?}", poll_data.3);
        }

        Ok(())
    }

    pub async fn get_results(&self, poll_id: u64) -> Result<()> {
        let poll_data = self.contract
            .get_poll(U256::from(poll_id))
            .call()
            .await?;

        let results = self.contract
            .get_poll_results(U256::from(poll_id))
            .call()
            .await?;

        let total_votes = self.contract
            .get_total_votes(U256::from(poll_id))
            .call()
            .await?;

        println!("\n📊 Poll Results for: {}", poll_data.1);
        println!("{}", "=".repeat(50));
        
        for (i, votes) in results.iter().enumerate() {
            let percentage = if total_votes > U256::zero() {
                (votes.as_u64() * 100) / total_votes.as_u64()
            } else {
                0
            };
            
            let bar = "█".repeat((percentage / 2) as usize);
            println!("{}: {:>3} votes ({:>2}%) {}", 
                poll_data.2[i], votes, percentage, bar);
        }
        
        println!("{}", "=".repeat(50));
        println!("Total votes: {}", total_votes);

        Ok(())
    }

    pub async fn close_poll(&self, poll_id: u64) -> Result<()> {
        println!("Closing poll {}", poll_id);

        let contract_call = self.contract.close_poll(U256::from(poll_id));
        let tx = contract_call.send().await?;

        let receipt = tx.await?;
        
        if let Some(receipt) = receipt {
            println!("✅ Poll closed successfully!");
            println!("Transaction hash: {:?}", receipt.transaction_hash);
        }

        Ok(())
    }

    pub async fn my_polls(&self) -> Result<()> {
        let address = self.signer.address();
        let created_polls = self.contract
            .get_user_created_polls(address)
            .call()
            .await?;

        println!("\n📝 Your Created Polls:");
        if created_polls.is_empty() {
            println!("You haven't created any polls yet.");
            return Ok(());
        }

        for poll_id in created_polls {
            let poll_data = self.contract
                .get_poll(poll_id)
                .call()
                .await?;
            
            let is_active = self.contract
                .is_poll_active(poll_id)
                .call()
                .await?;

            let status = if is_active { "🟢 Active" } else { "🔴 Closed" };
            println!("\nPoll #{}: {}", poll_id, poll_data.1);
            println!("  Status: {}", status);
        }

        Ok(())
    }

    pub async fn my_votes(&self) -> Result<()> {
        let address = self.signer.address();
        let voted_polls = self.contract
            .get_user_voted_polls(address)
            .call()
            .await?;

        println!("\n🗳️  Polls You've Voted On:");
        if voted_polls.is_empty() {
            println!("You haven't voted on any polls yet.");
            return Ok(());
        }

        for poll_id in voted_polls {
            let poll_data = self.contract
                .get_poll(poll_id)
                .call()
                .await?;
            
            println!("\nPoll #{}: {}", poll_id, poll_data.1);
        }

        Ok(())
    }

    pub async fn export_poll(&self, poll_id: u64, format: &str, output_path: Option<String>) -> Result<()> {
        println!("{} {} {} {}", "📊 Exporting poll".cyan().bold(), poll_id.to_string().yellow(), "in".cyan().bold(), format.yellow());

        let poll_data = self.contract.get_poll(U256::from(poll_id)).call().await?;
        let results = self.contract.get_poll_results(U256::from(poll_id)).call().await?;
        let total_votes = self.contract.get_total_votes(U256::from(poll_id)).call().await?;

        let created_at = DateTime::from_timestamp(poll_data.4.as_u64() as i64, 0)
            .unwrap_or_default()
            .format("%Y-%m-%d %H:%M:%S UTC")
            .to_string();

        let end_time = DateTime::from_timestamp(poll_data.5.as_u64() as i64, 0)
            .unwrap_or_default()
            .format("%Y-%m-%d %H:%M:%S UTC")
            .to_string();


        let export_data = PollExport {
            id: poll_id,
            question: poll_data.1.clone(),
            creator: format!("{:?}", poll_data.3),
            created_at,
            end_time,
            is_active: poll_data.6,
            total_votes: total_votes.as_u64(),
            options: poll_data.2.clone(),
            votes: results.iter().map(|v| v.as_u64()).collect(),
        };

        let output = match format.to_lowercase().as_str() {
            "json" => {
                let json_output = serde_json::to_string_pretty(&export_data)?;
                if let Some(path) = output_path {
                    std::fs::write(&path, &json_output)?;
                    println!("{} {}", "✅ Exported to:".green().bold(), path.yellow());
                } else {
                    println!("{}", json_output);
                }
            }
            "csv" => {
                let mut csv_output = String::new();
                csv_output.push_str("id,question,creator,created_at,end_time,is_active,total_votes,option,votes\n");
                
                for (i, option) in export_data.options.iter().enumerate() {
                    csv_output.push_str(&format!(
                        "{},{},{},{},{},{},{},{},{}\n",
                        export_data.id,
                        export_data.question.replace(',', ";"),
                        export_data.creator,
                        export_data.created_at,
                        export_data.end_time,
                        export_data.is_active,
                        export_data.total_votes,
                        option.replace(',', ";"),
                        export_data.votes[i]
                    ));
                }

                if let Some(path) = output_path {
                    std::fs::write(&path, &csv_output)?;
                    println!("{} {}", "✅ Exported to:".green().bold(), path.yellow());
                } else {
                    println!("{}", csv_output);
                }
            }
            "table" => {
                let table = Table::new([export_data]).to_string();
                if let Some(path) = output_path {
                    std::fs::write(&path, &table)?;
                    println!("{} {}", "✅ Exported to:".green().bold(), path.yellow());
                } else {
                    println!("{}", table);
                }
            }
            _ => anyhow::bail!("Unsupported format: {}. Use json, csv, or table", format),
        };

        Ok(())
    }

    pub async fn generate_analytics(&self, poll_id: Option<u64>) -> Result<()> {
        match poll_id {
            Some(id) => {
                println!("{} {}", "📈 Generating analytics for poll".cyan().bold(), id.to_string().yellow());
                self.generate_single_poll_analytics(id).await
            }
            None => {
                println!("{}", "📈 Generating comprehensive analytics for all polls".cyan().bold());
                self.generate_all_polls_analytics().await
            }
        }
    }

    async fn generate_single_poll_analytics(&self, poll_id: u64) -> Result<()> {
        let poll_data = self.contract.get_poll(U256::from(poll_id)).call().await?;
        let results = self.contract.get_poll_results(U256::from(poll_id)).call().await?;
        let total_votes = self.contract.get_total_votes(U256::from(poll_id)).call().await?;

        let created_at = DateTime::from_timestamp(poll_data.4.as_u64() as i64, 0)
            .unwrap_or_default()
            .format("%Y-%m-%d %H:%M:%S UTC")
            .to_string();

        let mut options_detail: Vec<OptionDetail> = Vec::new();
        let mut leading_option = String::new();
        let mut max_votes = 0u64;

        for (i, option) in poll_data.2.iter().enumerate() {
            let votes = results[i].as_u64();
            let percentage = if total_votes.as_u64() > 0 {
                (votes as f64 / total_votes.as_u64() as f64) * 100.0
            } else {
                0.0
            };

            if votes > max_votes {
                max_votes = votes;
                leading_option = option.clone();
            }

            options_detail.push(OptionDetail {
                index: i,
                option: option.clone(),
                votes,
                percentage,
            });
        }

        let second_highest = results.iter()
            .map(|v| v.as_u64())
            .filter(|&v| v != max_votes)
            .max()
            .unwrap_or(0);

        let margin = if total_votes.as_u64() > 0 {
            ((max_votes as f64 - second_highest as f64) / total_votes.as_u64() as f64) * 100.0
        } else {
            0.0
        };

        let time_remaining = if poll_data.6 {
            let now = chrono::Utc::now().timestamp() as u64;
            let end_time = poll_data.5.as_u64();
            if end_time > now {
                let remaining_seconds = end_time - now;
                let days = remaining_seconds / 86400;
                let hours = (remaining_seconds % 86400) / 3600;
                Some(format!("{} days, {} hours", days, hours))
            } else {
                Some("Expired".to_string())
            }
        } else {
            Some("Closed".to_string())
        };

        println!("\n{}", "📊 POLL ANALYTICS".cyan().bold().underline());
        println!("{}", "═".repeat(50).cyan());
        println!("{} {} - {}", "Poll ID:".yellow().bold(), poll_id.to_string().white(), poll_data.1.white().bold());
        println!("{} {}", "Total Votes:".yellow().bold(), total_votes.to_string().green().bold());
        println!("{} {}", "Leading Option:".yellow().bold(), leading_option.green().bold());
        println!("{} {:.1}%", "Margin:".yellow().bold(), margin);
        if let Some(time) = time_remaining {
            println!("{} {}", "Time Remaining:".yellow().bold(), time.white());
        }
        println!("{} {}", "Created:".yellow().bold(), created_at.white());
        
        println!("\n{}", "📋 DETAILED RESULTS".cyan().bold());
        println!("{}", "─".repeat(50).cyan());
        
        for detail in &options_detail {
            let bar_length = (detail.percentage / 2.0) as usize;
            let bar = "█".repeat(bar_length);
            println!("{}: {} votes ({:.1}%) {}",
                detail.option.white().bold(),
                detail.votes.to_string().yellow(),
                detail.percentage,
                bar.green()
            );
        }

        Ok(())
    }

    async fn generate_all_polls_analytics(&self) -> Result<()> {
        let poll_count = self.contract.poll_count().call().await?;
        
        println!("\n{}", "📊 COMPREHENSIVE POLL ANALYTICS".cyan().bold().underline());
        println!("{}", "═".repeat(60).cyan());
        
        let mut total_system_votes = 0u64;
        let mut active_polls = 0u64;
        let mut closed_polls = 0u64;
        
        for i in 0..poll_count.as_u64() {
            let poll_data = self.contract.get_poll(U256::from(i)).call().await?;
            let total_votes = self.contract.get_total_votes(U256::from(i)).call().await?;
            let is_active = poll_data.6 && chrono::Utc::now().timestamp() as u64 <= poll_data.5.as_u64();
            
            total_system_votes += total_votes.as_u64();
            if is_active {
                active_polls += 1;
            } else {
                closed_polls += 1;
            }
            
            println!("\n{} {} - {}", "Poll".yellow().bold(), i.to_string().white(), poll_data.1.white().bold());
            println!("  {} {} | {} {}", 
                "Votes:".cyan(), total_votes.to_string().green(),
                "Status:".cyan(), if is_active { "🟢 Active".green() } else { "🔴 Closed".red() }
            );
        }
        
        println!("\n{}", "📈 SYSTEM SUMMARY".cyan().bold().underline());
        println!("{}", "═".repeat(30).cyan());
        println!("{} {}", "Total Polls:".yellow().bold(), poll_count.to_string().white());
        println!("{} {}", "Active Polls:".yellow().bold(), active_polls.to_string().green());
        println!("{} {}", "Closed Polls:".yellow().bold(), closed_polls.to_string().red());
        println!("{} {}", "Total Votes Cast:".yellow().bold(), total_system_votes.to_string().cyan());
        
        if poll_count.as_u64() > 0 {
            let avg_votes = total_system_votes as f64 / poll_count.as_u64() as f64;
            println!("{} {:.1}", "Average Votes per Poll:".yellow().bold(), avg_votes);
        }

        Ok(())
    }

    // Enhanced methods for new functionality
    pub async fn vote_as_delegate(&self, poll_id: u64, option_index: u64, delegator: &str) -> Result<()> {
        let delegator_addr: Address = delegator.parse()?;
        println!("{} {} {} {} {} {}", 
            "🗳️ Voting as delegate on poll".cyan().bold(), 
            poll_id.to_string().yellow(), 
            "with option".cyan().bold(), 
            option_index.to_string().yellow(),
            "for".cyan().bold(),
            delegator.yellow()
        );

        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner().template("{spinner:.green} {msg}").unwrap());
        pb.set_message("Submitting delegate vote...");
        pb.enable_steady_tick(std::time::Duration::from_millis(100));

        let contract_call = self.contract.vote_as_delegate(
            U256::from(poll_id), 
            U256::from(option_index), 
            delegator_addr
        );
        let tx = contract_call.send().await?;
        let receipt = tx.await?;
        pb.finish_and_clear();
        
        if let Some(receipt) = receipt {
            println!("{}", "✅ Delegate vote cast successfully!".green().bold());
            println!("{} {:?}", "Transaction hash:".cyan().bold(), receipt.transaction_hash);
        }

        Ok(())
    }

    pub async fn set_delegate(&self, delegate: &str) -> Result<()> {
        let delegate_addr: Address = delegate.parse()?;
        println!("{} {}", "👥 Setting delegate to".cyan().bold(), delegate.yellow());

        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner().template("{spinner:.green} {msg}").unwrap());
        pb.set_message("Setting delegate...");
        pb.enable_steady_tick(std::time::Duration::from_millis(100));

        let contract_call = self.contract.set_delegate(delegate_addr);
        let tx = contract_call.send().await?;
        let receipt = tx.await?;
        pb.finish_and_clear();
        
        if let Some(receipt) = receipt {
            println!("{}", "✅ Delegate set successfully!".green().bold());
            println!("{} {:?}", "Transaction hash:".cyan().bold(), receipt.transaction_hash);
        }

        Ok(())
    }

    pub async fn remove_delegate(&self) -> Result<()> {
        println!("{}", "👥 Removing current delegate".cyan().bold());

        let pb = ProgressBar::new_spinner();
        pb.set_style(ProgressStyle::default_spinner().template("{spinner:.green} {msg}").unwrap());
        pb.set_message("Removing delegate...");
        pb.enable_steady_tick(std::time::Duration::from_millis(100));

        let contract_call = self.contract.remove_delegate();
        let tx = contract_call.send().await?;
        let receipt = tx.await?;
        pb.finish_and_clear();
        
        if let Some(receipt) = receipt {
            println!("{}", "✅ Delegate removed successfully!".green().bold());
            println!("{} {:?}", "Transaction hash:".cyan().bold(), receipt.transaction_hash);
        }

        Ok(())
    }

    pub async fn extend_poll(&self, poll_id: u64, additional_hours: u64) -> Result<()> {
        let additional_seconds = additional_hours * 3600;
        println!("{} {} {} {} {}", 
            "⏰ Extending poll".cyan().bold(), 
            poll_id.to_string().yellow(), 
            "by".cyan().bold(),
            additional_hours.to_string().yellow(),
            "hours".cyan().bold()
        );

        let contract_call = self.contract.extend_poll(U256::from(poll_id), U256::from(additional_seconds));
        let tx = contract_call.send().await?;
        let receipt = tx.await?;
        
        if let Some(receipt) = receipt {
            println!("{}", "✅ Poll extended successfully!".green().bold());
            println!("{} {:?}", "Transaction hash:".cyan().bold(), receipt.transaction_hash);
        }

        Ok(())
    }

    pub async fn check_token_balance(&self, token_address: Option<String>, check_address: Option<String>) -> Result<()> {
        let address_to_check = if let Some(addr) = check_address {
            addr.parse::<Address>()?
        } else {
            self.signer.address()
        };

        if let Some(token_addr) = token_address {
            let token_address: Address = token_addr.parse()?;
            let token = GovernanceToken::new(token_address, self.signer.clone());
            
            let balance = token.balance_of(address_to_check).call().await?;
            let name = token.name().call().await?;
            let symbol = token.symbol().call().await?;
            let decimals = token.decimals().call().await?;
            
            let balance_formatted = balance.as_u128() as f64 / 10_f64.powi(decimals as i32);
            
            println!("\n💰 Token Balance Information:");
            println!("{} {}", "Token:".yellow().bold(), format!("{} ({})", name, symbol).green());
            println!("{} {:.2}", "Balance:".yellow().bold(), balance_formatted);
            println!("{} {:?}", "Address:".yellow().bold(), address_to_check);
        } else if let Some(ref gov_token) = self.governance_token {
            let balance = gov_token.balance_of(address_to_check).call().await?;
            let voting_power = gov_token.get_voting_power(address_to_check).call().await?;
            let name = gov_token.name().call().await?;
            let symbol = gov_token.symbol().call().await?;
            
            let balance_formatted = balance.as_u128() as f64 / 1e18;
            let voting_power_formatted = voting_power.as_u128() as f64 / 1e18;
            
            println!("\n💰 Governance Token Information:");
            println!("{} {}", "Token:".yellow().bold(), format!("{} ({})", name, symbol).green());
            println!("{} {:.2}", "Balance:".yellow().bold(), balance_formatted);
            println!("{} {:.2}", "Voting Power:".yellow().bold(), voting_power_formatted);
            println!("{} {:?}", "Address:".yellow().bold(), address_to_check);
        } else {
            anyhow::bail!("No token address provided and no governance token set");
        }

        Ok(())
    }

    pub async fn view_user_stats(&self, user_address: Option<String>) -> Result<()> {
        let address_to_check = if let Some(addr) = user_address {
            addr.parse::<Address>()?
        } else {
            self.signer.address()
        };

        let (polls_created, polls_voted, total_voting_weight) = self.contract
            .get_user_stats(address_to_check)
            .call()
            .await?;

        println!("\n📊 User Statistics:");
        println!("{} {:?}", "Address:".yellow().bold(), address_to_check);
        println!("{} {}", "Polls Created:".yellow().bold(), polls_created.to_string().green());
        println!("{} {}", "Polls Voted On:".yellow().bold(), polls_voted.to_string().green());
        println!("{} {}", "Total Voting Weight:".yellow().bold(), total_voting_weight.to_string().cyan());

        Ok(())
    }

    pub async fn view_delegation_info(&self, user_address: Option<String>) -> Result<()> {
        let address_to_check = if let Some(addr) = user_address {
            addr.parse::<Address>()?
        } else {
            self.signer.address()
        };

        let delegate = self.contract.get_delegate(address_to_check).call().await?;
        let delegators = self.contract.get_delegators(address_to_check).call().await?;

        println!("\n👥 Delegation Information:");
        println!("{} {:?}", "Address:".yellow().bold(), address_to_check);
        
        if delegate != Address::zero() {
            println!("{} {:?}", "Delegated To:".yellow().bold(), delegate);
        } else {
            println!("{} {}", "Delegated To:".yellow().bold(), "None".red());
        }

        if !delegators.is_empty() {
            println!("{} {}", "Delegators Count:".yellow().bold(), delegators.len().to_string().green());
            println!("{}", "Delegators:".yellow().bold());
            for (i, delegator) in delegators.iter().enumerate() {
                println!("  {}: {:?}", i + 1, delegator);
            }
        } else {
            println!("{} {}", "Delegators:".yellow().bold(), "None".red());
        }

        Ok(())
    }

    pub async fn list_enhanced_polls(&self, category: Option<String>, tag: Option<String>, active_only: bool) -> Result<()> {
        if let Some(tag_str) = tag {
            // Filter by tag
            let poll_ids = self.contract.get_polls_by_tag(tag_str.clone()).call().await?;
            println!("\n📋 Polls with tag '{}':", tag_str.green());
            self.display_poll_list(poll_ids, active_only).await?;
        } else if let Some(category_str) = category {
            // Filter by category
            let category_u8 = category_to_u8(&category_str)?;
            let poll_ids = self.contract.get_polls_by_category(category_u8).call().await?;
            println!("\n📋 {} Polls:", u8_to_category(category_u8).green());
            self.display_poll_list(poll_ids, active_only).await?;
        } else {
            // List all polls
            let poll_count = self.contract.poll_count().call().await?;
            let poll_ids: Vec<U256> = (0..poll_count.as_u64()).map(U256::from).collect();
            
            if active_only {
                println!("\n📋 Active Polls:");
            } else {
                println!("\n📋 All Polls:");
            }
            
            self.display_poll_list(poll_ids, active_only).await?;
        }

        Ok(())
    }

    async fn display_poll_list(&self, poll_ids: Vec<U256>, active_only: bool) -> Result<()> {
        if poll_ids.is_empty() {
            println!("No polls found.");
            return Ok(());
        }

        println!("Total polls: {}", poll_ids.len());
        
        for poll_id in poll_ids {
            let poll = self.contract.get_poll(poll_id).call().await?;
            let is_active = self.contract.is_poll_active(poll_id).call().await?;
            
            if active_only && !is_active {
                continue;
            }
            
            let status_emoji = if is_active { "🟢" } else { "🔴" };
            let status_text = if is_active { "Active".green() } else { "Closed".red() };
            
            println!("\n{} Poll #{}: {}", status_emoji, poll_id, poll.1); // poll.1 is question
            println!("  Status: {}", status_text);
            println!("  Type: {}", u8_to_poll_type(poll.7)); // poll.7 is pollType
            println!("  Category: {}", u8_to_category(poll.8)); // poll.8 is category
            println!("  Options: {}", poll.2.len()); // poll.2 is options
            println!("  Total Votes: {}", poll.10); // poll.10 is totalVotes
            println!("  Creator: {:?}", poll.3); // poll.3 is creator
            
            if !poll.13.is_empty() { // poll.13 is tags
                println!("  Tags: {:?}", poll.13);
            }
        }

        Ok(())
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenv::dotenv().ok();
    
    let cli = Cli::parse();

    // Default values - can be overridden with environment variables
    let rpc_url = std::env::var("RPC_URL").unwrap_or_else(|_| "http://localhost:8545".to_string());
    let private_key = std::env::var("PRIVATE_KEY").unwrap_or_else(|_| {
        // Default Anvil test private key
        "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80".to_string()
    });
    let contract_address = std::env::var("CONTRACT_ADDRESS").unwrap_or_else(|_| {
        println!("⚠️  CONTRACT_ADDRESS not set, using placeholder");
        "0x5FbDB2315678afecb367f032d93F642f64180aa3".to_string()
    });

    let mut poll_manager = PollManager::new(&rpc_url, &private_key, &contract_address).await?;
    
    // Set governance token if provided
    if let Ok(token_address) = std::env::var("GOVERNANCE_TOKEN_ADDRESS") {
        poll_manager.set_governance_token(&token_address).await?;
    }

    match cli.command {
        Commands::Create { 
            question, 
            options, 
            duration, 
            poll_type, 
            category, 
            min_participation, 
            token_address, 
            min_token_balance, 
            description, 
            tags 
        } => {
            let option_list: Vec<String> = options
                .split(',')
                .map(|s| s.trim().to_string())
                .collect();
            
            if option_list.len() < 2 {
                anyhow::bail!("Poll must have at least 2 options");
            }
            
            poll_manager.create_enhanced_poll(
                question, 
                option_list, 
                duration, 
                &poll_type, 
                &category, 
                min_participation, 
                token_address, 
                min_token_balance, 
                description, 
                tags
            ).await?;
        }
        Commands::Vote { poll_id, option } => {
            poll_manager.vote(poll_id, option).await?;
        }
        Commands::VoteDelegate { poll_id, option, delegator } => {
            poll_manager.vote_as_delegate(poll_id, option, &delegator).await?;
        }
        Commands::SetDelegate { delegate } => {
            poll_manager.set_delegate(&delegate).await?;
        }
        Commands::RemoveDelegate => {
            poll_manager.remove_delegate().await?;
        }
        Commands::View { poll_id } => {
            poll_manager.view_poll(poll_id).await?;
        }
        Commands::List { category, tag, active_only } => {
            poll_manager.list_enhanced_polls(category, tag, active_only).await?;
        }
        Commands::Results { poll_id } => {
            poll_manager.get_results(poll_id).await?;
        }
        Commands::Close { poll_id } => {
            poll_manager.close_poll(poll_id).await?;
        }
        Commands::Extend { poll_id, hours } => {
            poll_manager.extend_poll(poll_id, hours).await?;
        }
        Commands::MyPolls => {
            poll_manager.my_polls().await?;
        }
        Commands::MyVotes => {
            poll_manager.my_votes().await?;
        }
        Commands::MyStats => {
            poll_manager.view_user_stats(None).await?;
        }
        Commands::Delegation { address } => {
            poll_manager.view_delegation_info(address).await?;
        }
        Commands::TokenBalance { token, address } => {
            poll_manager.check_token_balance(token, address).await?;
        }
        Commands::Export { poll_id, format, output } => {
            poll_manager.export_poll(poll_id, &format, output).await?;
        }
        Commands::Analytics { poll_id } => {
            poll_manager.generate_analytics(poll_id).await?;
        }
    }

    Ok(())
}
