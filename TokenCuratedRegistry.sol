// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IERC20 {
    function transfer(address recipient, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract TokenCuratedRegistry {
    struct Listing {
        address applicant;
        uint256 stake;
        uint256 applicationTime;
        bool accepted;
        bool exists;
        uint256 voteCount;
        uint256 challengeCount;
    }

    IERC20 public token;
    uint256 public applicationStake;
    uint256 public votingPeriod; // in seconds
    uint256 public rewardPercentage; // percentage (e.g., 10 for 10%)

    mapping(string => Listing) public listings;
    mapping(string => mapping(address => bool)) public votes;
    mapping(string => mapping(address => bool)) public hasVotedInSupport;
    mapping(string => address[]) public voters;

    event Applied(string listingName, address applicant, uint256 stake);
    event Voted(string listingName, address voter, bool inSupport);
    event Accepted(string listingName);
    event Rejected(string listingName, address challenger);
    event RewardDistributed(string listingName, address voter, uint256 reward);

    constructor(IERC20 _token, uint256 _minDeposit, uint256 _votingPeriod, uint256 _rewardPercentage) {
        token = _token;
        applicationStake = _minDeposit;
        votingPeriod = _votingPeriod;
        rewardPercentage = _rewardPercentage;
    }

    /// @dev Apply to be listed in the registry
    function applyListing(string memory listingName) external {
        require(!listings[listingName].exists, "Listing already exists");

        // Transfer tokens from applicant to contract as stake
        require(token.transferFrom(msg.sender, address(this), applicationStake), "Token transfer failed");

        listings[listingName] = Listing({
            applicant: msg.sender,
            stake: applicationStake,
            applicationTime: block.timestamp,
            accepted: false,
            exists: true,
            voteCount: 0,
            challengeCount: 0
        });

        emit Applied(listingName, msg.sender, applicationStake);
    }

    /// @dev Challenge a listing in the registry
    function challenge(string memory listingName) external {
        Listing storage listing = listings[listingName];
        require(listing.exists, "Listing does not exist");
        require(block.timestamp < listing.applicationTime + votingPeriod, "Voting period has ended");
        require(!listing.accepted, "Listing already accepted");

        listing.challengeCount++;

        emit Rejected(listingName, msg.sender);
    }

    /// @dev Vote on a listing's acceptance
    function vote(string memory listingName, bool inSupport) external {
        Listing storage listing = listings[listingName];
        require(listing.exists, "Listing does not exist");
        require(block.timestamp < listing.applicationTime + votingPeriod, "Voting period has ended");
        require(!votes[listingName][msg.sender], "Already voted");

        votes[listingName][msg.sender] = true;
        voters[listingName].push(msg.sender);

        if (inSupport) {
            listing.voteCount++;
            hasVotedInSupport[listingName][msg.sender] = true;
        } else {
            listing.challengeCount++;
        }

        emit Voted(listingName, msg.sender, inSupport);
    }

    /// @dev Finalize the voting and update listing status
    function finalize(string memory listingName) external {
        Listing storage listing = listings[listingName];
        require(listing.exists, "Listing does not exist");
        require(block.timestamp >= listing.applicationTime + votingPeriod, "Voting period not ended");

        if (listing.voteCount > listing.challengeCount) {
            listing.accepted = true;
            emit Accepted(listingName);

            // Distribute rewards to voters who supported the accepted listing
            distributeRewards(listingName);
        } else {
            // If rejected, return the stake to the challenger(s)
            token.transfer(msg.sender, listing.stake);
            delete listings[listingName];
        }
    }

    /// @dev Distribute rewards to voters who voted with the winning side
    function distributeRewards(string memory listingName) internal {
        Listing storage listing = listings[listingName];
        uint256 rewardAmount = (listing.stake * rewardPercentage) / 100;
        uint256 rewardPerVoter = rewardAmount / listing.voteCount;

        for (uint256 i = 0; i < voters[listingName].length; i++) {
            address voter = voters[listingName][i];
            if (hasVotedInSupport[listingName][voter]) {
                token.transfer(voter, rewardPerVoter);
                emit RewardDistributed(listingName, voter, rewardPerVoter);
            }
        }
    }

    /// @dev View listing details
    function getListing(string memory listingName) external view returns (address, uint256, bool, uint256, uint256, uint256) {
        Listing storage listing = listings[listingName];
        return (
            listing.applicant,
            listing.stake,
            listing.accepted,
            listing.voteCount,
            listing.challengeCount,
            listing.applicationTime
        );
    }
}
