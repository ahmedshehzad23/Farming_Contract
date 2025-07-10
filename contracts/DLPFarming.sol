// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import "./IERC20.sol";

contract DLPFarming is
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable
{
    // Define role constants
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant STAKE = keccak256("STAKE");
    bytes32 public constant UNSTAKE = keccak256("UNSTAKE");

    uint256 private campaignCounter;
    uint256 private adminEntriesCounter;

    address private nativeCurrency;
    address private DLPToken;

    string private name;

    bool private featureToggle;

    // Struct to represent each currency
    struct Currency {
        uint256 rewardRatio;
        uint256 totalStake;
        bool isActive;
        uint8 decimals;
    }
    // Struct to represent user stakes
    struct Stake {
        uint256 amount;
        uint256 stakeTime;
        uint256 lastClaimTime;
    }
    // Struct for campaigns
    struct Campaign {
        uint256 campaignStartTime;
        uint256 campaignEndTime;
        string name;
        mapping(address => Currency) currencies;
        address[] currenciesArr;
    }

    // Mapping to store campaigns
    mapping(uint256 => Campaign) private campaigns;
    // Mapping to store user stakes per campaign and currency
    mapping(address => mapping(uint256 => mapping(address => Stake[]))) private stakes;
    mapping(address => bool) private VIPuser;
    mapping(address => mapping(uint256 => mapping(address => uint256))) private unclaimedRewards;
    mapping(bytes => bool) private usedSignature;
    mapping(address => bool) private signatureAdmin;
    mapping(bytes => bool) private txHashStatus;
    mapping(address => mapping(uint256 => mapping(address => uint256))) private claimedRewards;

    event Staked(
        address _user,
        address indexed _currency,
        uint256 _amount,
        uint256 indexed _campaignId,
        uint256 indexed _adminEntriesCounter,
        uint256 _time
    );
    event AdminAddStake(
        address _user,
        address indexed _currency,
        uint256 _amount,
        uint256 indexed _campaignId,
        bytes _txHash,
        uint256 indexed _adminEntriesCounter,
        uint256 _time
    );
    event VIPStakeAdded(
        address indexed _user,
        address indexed _currency,
        uint256 _amount,
        uint256 indexed _campaignId,
        uint256 _time
    );
    event Unstake(
        address _user,
        address indexed _currency,
        uint256 _amount,
        uint256 indexed _campaignId,
        uint256 indexed _adminEntriesCounter,
        uint256 _time
    );
    event AdminAddUnstake(
        address _user,
        address indexed _currency,
        uint256 _amount,
        uint256 indexed _campaignId,
        bytes _txHash,
        uint256 indexed _adminEntriesCounter,
        uint256 _time
    );
    event CampaignCreated(
        uint256 indexed _campaignId,
        string indexed _name,
        uint256 indexed _time
    );
    event RewardClaimed(
        address indexed _user,
        uint256 indexed _campaignId,
        address indexed _currency,
        uint256 _amount,
        uint256 _time
    );
    event CurrencyAddedToCampaign(
        uint256 indexed _campaignId,
        address indexed _currency,
        uint256 indexed _rewardRatio,
        uint8 _decimals,
        uint256 _time
    );
    event SignatureAdminAdded(
        address indexed _adder,
        address indexed _adminAddress,
        uint256 indexed _time
    );
    event SignatureAdminRemoved(
        address indexed _remover,
        address indexed _adminAddress,
        uint256 indexed _time
    );
    event CampaignStartTimeUpdated(
        uint256 indexed _campaignId,
        uint256 _newStartTime,
        address indexed _admin,
        uint256 _time
    );
    event CampaignEndTimeUpdated(
        uint256 indexed _campaignId,
        uint256 _newEndTime,
        address indexed _admin,
        uint256 _time
    );
    event MultiChainFeatureToggle(
        address indexed _admin,
        bool indexed _status
    );

    // Modifier to restrict access to the admin
    modifier onlyAdmin() {
        require(
            hasRole(ADMIN_ROLE, msg.sender),
            "Only admin can perform this action"
        );
        _;
    }

    function initialize(
        string memory _protocolName,
        address _nativeCurrency,
        address _DLPToken,
        bool _featureToggle
    ) public initializer {
        __ReentrancyGuard_init();
        __EIP712_init("DLP", "1");
        name = _protocolName;

        nativeCurrency = _nativeCurrency;
        DLPToken = _DLPToken;
        VIPuser[msg.sender] = true;
        signatureAdmin[msg.sender] = true;
        featureToggle = _featureToggle;

        _setupRole(ADMIN_ROLE, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function setFeatureToggle(bool _featureToggle) external onlyAdmin{
        require(_featureToggle != featureToggle,"DLP Contract: Status same as old");

        featureToggle = _featureToggle;

        emit MultiChainFeatureToggle(msg.sender, _featureToggle);
    }

    function createCampaign(
        string memory _name,
        uint256 _campaignStartTime,
        uint256 _campaignEndTime
    ) external onlyAdmin {
        require(
            _campaignStartTime < _campaignEndTime,
            "DLP Contract: Start time must be before end time"
        );

        require(
            _campaignStartTime > block.timestamp,
            "DLP Contract: Start time should be in future"
        );

        campaigns[campaignCounter].name = _name;
        campaigns[campaignCounter].campaignStartTime = _campaignStartTime;
        campaigns[campaignCounter].campaignEndTime = _campaignEndTime;

        emit CampaignCreated(campaignCounter, _name, block.timestamp);

        campaignCounter++;
    }

    function addCurrencyToCampaign(
        uint256 _campaignId,
        address _currency,
        uint256 _rewardRatio,
        uint8 _decimals
    ) external onlyAdmin {
        require(
            _campaignId < campaignCounter,
            "DLP Contract: Campaign does not exist"
        );
        require(
            _rewardRatio > 0,
            "DLP Contract: Reward ratio should be greater than 0"
        );
        require(
            campaigns[_campaignId].currencies[_currency].rewardRatio == 0,
            "DLP Contract: Currency already exist"
        );
        require(
            _decimals > 0 && 
            _decimals <= 18,
            "DLP Contract: Invalid decimals value"
        );

        campaigns[_campaignId].currencies[_currency] = Currency({
            rewardRatio: _rewardRatio,
            totalStake: 0,
            isActive: true,
            decimals: _decimals
        });

        campaigns[_campaignId].currenciesArr.push(_currency);

        emit CurrencyAddedToCampaign(
            _campaignId,
            _currency,
            _rewardRatio,
            _decimals,
            block.timestamp
        );
    }

    function stake(
        uint256 _campaignId,
        address _currency,
        uint256 _amount
    ) external payable nonReentrant {
        require(
            block.timestamp >= campaigns[_campaignId].campaignStartTime &&
            block.timestamp <= campaigns[_campaignId].campaignEndTime,
            "DLP Contract: Staking not active"
        );

        Currency storage currency = campaigns[_campaignId].currencies[_currency];

        require(currency.isActive, "DLP Contract: Currency is not active");

        uint256 stakeAmount;
        
        if (_currency == nativeCurrency) {
            require(msg.value > 0, "DLP Contract: Invalid amount");
            stakeAmount = msg.value;
        } else {
            require(_amount > 0, "DLP Contract: Invalid amount");
            
            IERC20 token = IERC20(_currency);
            require(
                token.transferFrom(msg.sender, address(this), _amount),
                "DLP Contract: Token transfer failed"
            );

            stakeAmount = _amount;
        }

        // Store stake entry
        stakes[msg.sender][_campaignId][_currency].push(
            Stake({
                amount: stakeAmount,
                stakeTime: block.timestamp,
                lastClaimTime: block.timestamp
            })
        );

        // Update total stake
        currency.totalStake += stakeAmount;

        // Determine admin entry counter only on Ethereum (chain ID 1)
        uint256 entryCounter;
        
        if (block.chainid == 1){
            adminEntriesCounter++;
            entryCounter = adminEntriesCounter;
        } else {
            entryCounter = 0;
        }

        // Emit event (removes redundant emit calls)
        emit Staked(
            msg.sender,
            _currency,
            stakeAmount,
            _campaignId,
            entryCounter,
            block.timestamp
        );
    }

    function addVIPStake(
        address[] memory _user,
        uint256[] memory _campaignId,
        address[] memory _currency,
        uint256[] memory _amount
    ) external payable onlyAdmin {

        require(featureToggle,"DLP Contract: Feature disabled");
        require(
            _user.length == _campaignId.length &&
            _campaignId.length == _currency.length &&
            _currency.length == _amount.length,
            "DLP Contract: Invalid length of parameters"
        );

        uint256 totalAmount;

        for (uint256 index = 0; index < _user.length; index++) {

            require(
                _amount[index] > 0,
                "DLP Contract: Invalid amount"
            );

            totalAmount = totalAmount + _amount[index];

        }

        require(
            totalAmount == msg.value, 
            "DLP Contract: Invalid total amount"
        );

        for (uint256 index = 0; index < _user.length; index++) {
            require(
                block.timestamp >= campaigns[_campaignId[index]].campaignStartTime &&
                block.timestamp <= campaigns[_campaignId[index]].campaignEndTime,
                "DLP Contract: Staking not active"
            );

            require(
                _user[index] != address(0),
                "DLP Contract: Invalid address"
            );

            Currency storage currency = campaigns[_campaignId[index]].currencies[_currency[index]];

            require(
                currency.isActive, 
                "DLP Contract: Currency is not active"
            );

            stakes[_user[index]][_campaignId[index]][_currency[index]].push(
                Stake({
                    amount: _amount[index],
                    stakeTime: block.timestamp,
                    lastClaimTime: block.timestamp
                })
            );

            currency.totalStake += _amount[index];

            VIPuser[_user[index]] = true;

            emit VIPStakeAdded(
                _user[index],
                _currency[index],
                _amount[index],
                _campaignId[index],
                block.timestamp
            );
        }
    }

    function unstake(
        uint256 _campaignId,
        address _currency,
        uint256 _amount
    ) external nonReentrant {
        Currency storage currency = campaigns[_campaignId].currencies[_currency];
        require(
            currency.isActive, 
            "DLP Contract: Currency is not active"
        );

        Stake[] storage userStakes = stakes[msg.sender][_campaignId][_currency];
        require(
            userStakes.length > 0, 
            "DLP Contract: No stakes found"
        );
        require(
            _amount > 0, 
            "DLP Contract: Amount must be greater than zero"
        );

        uint256 totalStakedAmount;

        for (uint256 index = 0; index < userStakes.length; index++) {
            Stake storage stakeEntry = userStakes[index];

            totalStakedAmount = totalStakedAmount + stakeEntry.amount;
        }

        require(
            _amount <= totalStakedAmount,
            "DLP Contract: Amount greater than total staked amount"
        );

        uint256 remainingAmount = _amount;
        uint256 accumulatedRewards = 0;

        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage stakeEntry = userStakes[i];

            uint256 durationSinceLastClaim;
            uint256 stakingDuration;

            if (block.timestamp > campaigns[_campaignId].campaignEndTime) {
                durationSinceLastClaim = campaigns[_campaignId].campaignEndTime - stakeEntry.lastClaimTime;
                stakeEntry.lastClaimTime = campaigns[_campaignId].campaignEndTime;
                stakingDuration = campaigns[_campaignId].campaignEndTime - stakeEntry.stakeTime;
            } else {
                durationSinceLastClaim = block.timestamp - stakeEntry.lastClaimTime;
                stakeEntry.lastClaimTime = block.timestamp;
                stakingDuration = block.timestamp - stakeEntry.stakeTime;
            }

            accumulatedRewards += calculateUserReward(
                msg.sender,
                stakingDuration,
                durationSinceLastClaim,
                _currency,
                currency,
                stakeEntry
            );

            if (stakeEntry.amount <= remainingAmount) {
                remainingAmount -= stakeEntry.amount;
                currency.totalStake -= stakeEntry.amount;
                stakeEntry.amount = 0;
            } else {
                stakeEntry.amount -= remainingAmount;
                currency.totalStake -= remainingAmount;
                remainingAmount = 0;
            }
        }

        // Clean up zero-amount stakes
        _cleanZeroAmountStakes(userStakes);

        // Update claimable rewards
        unclaimedRewards[msg.sender][_campaignId][_currency] += accumulatedRewards;

        if (_currency == nativeCurrency && VIPuser[msg.sender]) {
            VIPuser[msg.sender] = false;
        }

        if (_currency == nativeCurrency) {
            payable(msg.sender).transfer(_amount);
        } else {
            IERC20 token = IERC20(_currency);
            require(
                token.transfer(msg.sender, _amount),
                "DLP Contract: Token transfer failed"
            );
        }

        uint256 entryCounter;
        
        if (block.chainid == 1){
            adminEntriesCounter++;
            entryCounter = adminEntriesCounter;
        } else {
            entryCounter = 0;
        }

        emit Unstake(
            msg.sender,
            _currency,
            _amount,
            _campaignId,
            entryCounter,
            block.timestamp
        );

    }

    function addAdminEntries(
        address[] memory _user,
        uint256[] memory _campaignId,
        address[] memory _currency,
        uint256[] memory _amount,
        uint256[] memory _stakeTime,
        bytes[] memory _txHash,
        uint256[] memory _adminEntriesCounter,
        bytes32[] memory _identifier
    ) external nonReentrant onlyAdmin{
        require(
            _user.length == _campaignId.length &&
            _campaignId.length == _currency.length &&
            _currency.length == _amount.length &&
            _amount.length == _stakeTime.length &&
            _stakeTime.length == _txHash.length &&
            _txHash.length == _adminEntriesCounter.length &&
            _adminEntriesCounter.length == _identifier.length,
            "DLP Contract: Invalid length of parameters"
        );

        for(uint256 index=0; index<_user.length; index++){

            if(_identifier[index] == STAKE){
                _adminAddStake(_user[index], _campaignId[index], _currency[index], _amount[index], _stakeTime[index], _txHash[index],_adminEntriesCounter[index]);
            }
            else if (_identifier[index] == UNSTAKE){
                _adminAddUnstake(_user[index], _campaignId[index], _currency[index], _amount[index], _stakeTime[index], _txHash[index],_adminEntriesCounter[index]);
            }
        }

    }

    function _adminAddStake(
        address _user,
        uint256 _campaignId,
        address _currency,
        uint256 _amount,
        uint256 _stakeTime,
        bytes memory _txHash,
        uint256 _adminEntriesCounter
    ) internal {
        adminEntriesCounter++;

        require(featureToggle,"DLP Contract: Feature disabled");
        require(_adminEntriesCounter == adminEntriesCounter,"DLP Contract: Unexpected entry counter value");
        require(
            _stakeTime >= campaigns[_campaignId].campaignStartTime &&
            _stakeTime <= campaigns[_campaignId].campaignEndTime,
            "DLP Contract: Staking not active"
        );

        require(
            !txHashStatus[_txHash],
            "DLP Contract: Tx Hash already used"
        );

        require(
            _user != address(0),
            "DLP Contract: Invalid address"
        );

        require(_amount > 0, "DLP Contract: Invalid amount");

        require(_stakeTime > 0, "DLP Contract: Invalid stake time");

        Currency storage currency = campaigns[_campaignId].currencies[_currency];

        require(currency.isActive, "DLP Contract: Currency is not active");

        stakes[_user][_campaignId][_currency].push(
            Stake({
                amount: _amount,
                stakeTime: _stakeTime,
                lastClaimTime: _stakeTime
            })
        );
        currency.totalStake += _amount;

        txHashStatus[_txHash] = true;

        emit AdminAddStake(
            _user,
            _currency,
            _amount,
            _campaignId,
            _txHash,
            adminEntriesCounter,
            block.timestamp
        );
    }

    function _adminAddUnstake(
        address _user,
        uint256 _campaignId,
        address _currency,
        uint256 _amount,
        uint256 _unstakeTime,
        bytes memory _txHash,
        uint256 _adminEntriesCounter
    ) internal {
        adminEntriesCounter++;

        require(featureToggle,"DLP Contract: Feature disabled");
        require(_adminEntriesCounter == adminEntriesCounter,"DLP Contract: Unexpected entry counter value");

        Currency storage currency = campaigns[_campaignId].currencies[_currency];

        require(
            currency.isActive, 
            "DLP Contract: Currency is not active"
        );

        Stake[] storage userStakes = stakes[_user][_campaignId][_currency];

        require(
            userStakes.length > 0, 
            "DLP Contract: No stakes found"
        );
        require(
            !txHashStatus[_txHash],
            "DLP Contract: Tx Hash already used"
        );
        require(
            _amount > 0,
            "DLP Contract: Amount must be greater than zero"
        );
        require(
            _unstakeTime > 0,
            "DLP Contract: Invalid stake time"
        );

        uint256 totalStakedAmount;

        for (uint256 index1 = 0; index1 < userStakes.length; index1++) {
            Stake storage stakeEntry = userStakes[index1];

            totalStakedAmount = totalStakedAmount + stakeEntry.amount;
        }

        require(
            _amount <= totalStakedAmount,
            "DLP Contract: Amount greater than total staked amount"
        );

        uint256 remainingAmount = _amount;
        uint256 accumulatedRewards = 0;

        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage stakeEntry = userStakes[i];

            uint256 durationSinceLastClaim;
            uint256 stakingDuration;

            if (_unstakeTime >campaigns[_campaignId].campaignEndTime) {
                durationSinceLastClaim = campaigns[_campaignId].campaignEndTime - stakeEntry.lastClaimTime;
                stakeEntry.lastClaimTime = campaigns[_campaignId].campaignEndTime;
                stakingDuration = campaigns[_campaignId].campaignEndTime - stakeEntry.stakeTime;
            } else {
                durationSinceLastClaim = _unstakeTime - stakeEntry.lastClaimTime;
                stakeEntry.lastClaimTime = _unstakeTime;
                stakingDuration = _unstakeTime - stakeEntry.stakeTime;
            }

            accumulatedRewards += calculateUserReward(
                _user,
                stakingDuration,
                durationSinceLastClaim,
                _currency,
                currency,
                stakeEntry
            );

            if (stakeEntry.amount <= remainingAmount) {
                remainingAmount -= stakeEntry.amount;
                currency.totalStake -= stakeEntry.amount;
                stakeEntry.amount = 0;
            } else {
                stakeEntry.amount -= remainingAmount;
                currency.totalStake -= remainingAmount;
                remainingAmount = 0;
            }
        }

        // Clean up zero-amount stakes
        _cleanZeroAmountStakes(userStakes);

        // Update claimable rewards
        unclaimedRewards[_user][_campaignId][_currency] += accumulatedRewards;

        txHashStatus[_txHash] = true;

        emit AdminAddUnstake(
            _user,
            _currency,
            _amount,
            _campaignId,
            _txHash,
            adminEntriesCounter,
            block.timestamp
        );
    }

    function claimRewards(
        uint256 _campaignId,
        address _currency,
        uint256 _salt,
        bytes memory _sig
    ) external nonReentrant {

        require(featureToggle,"DLP Contract: Feature disabled");
        require(
            !usedSignature[_sig], 
            "DLP Contract: Signature already used!"
        );

        bytes32 msgHash = getStandardMessageHash(
            _campaignId,
            _salt,
            msg.sender
        );

        require(
            signatureAdmin[ECDSAUpgradeable.recover(msgHash, _sig)],
            "DLP Contract: Invalid signer!"
        );

        uint256 totalReward = _claimRewards(_campaignId, _currency);

        require(
            totalReward > 0, 
            "DLP Contract: No rewards available"
        );

        claimedRewards[msg.sender][_campaignId][_currency] = claimedRewards[msg.sender][_campaignId][_currency] + totalReward;

        usedSignature[_sig] = true;

        IERC20 token = IERC20(DLPToken);
        token.mint(msg.sender, totalReward);
    }

    function claimAllFromCampaign(
        uint256 _campaignId,
        uint256 _salt,
        bytes memory _sig
    ) external nonReentrant {

        require(featureToggle,"DLP Contract: Feature disabled");
        require(
            !usedSignature[_sig], 
            "DLP Contract: Signature already used!"
        );

        bytes32 msgHash = getStandardMessageHash(
            _campaignId,
            _salt,
            msg.sender
        );

        require(
            signatureAdmin[ECDSAUpgradeable.recover(msgHash, _sig)],
            "DLP Contract: Invalid signer!"
        );

        address[] memory currencies = campaigns[_campaignId].currenciesArr;

        uint256 totalReward;

        for (uint256 index = 0; index < currencies.length; index++) {
            Stake[] storage userStakes = stakes[msg.sender][_campaignId][currencies[index]];

            if (userStakes.length > 0) {

                uint256 currencyReward = _claimRewards(
                    _campaignId,
                    currencies[index]
                );
                totalReward = totalReward + currencyReward;
                claimedRewards[msg.sender][_campaignId][currencies[index]] = claimedRewards[msg.sender][_campaignId][currencies[index]] + currencyReward;

            } else if (unclaimedRewards[msg.sender][_campaignId][currencies[index]] > 0) {

                totalReward = totalReward + unclaimedRewards[msg.sender][_campaignId][currencies[index]];
                claimedRewards[msg.sender][_campaignId][currencies[index]] = claimedRewards[msg.sender][_campaignId][currencies[index]] + unclaimedRewards[msg.sender][_campaignId][currencies[index]];

                emit RewardClaimed(
                    msg.sender,
                    _campaignId,
                    currencies[index],
                    unclaimedRewards[msg.sender][_campaignId][
                        currencies[index]
                    ],
                    block.timestamp
                );

                unclaimedRewards[msg.sender][_campaignId][currencies[index]] = 0;
            }
        }

        require(totalReward > 0, "DLP Contract: No rewards available");

        usedSignature[_sig] = true;

        IERC20 token = IERC20(DLPToken);
        token.mint(msg.sender, totalReward);
    }

    function _claimRewards(
        uint256 _campaignId,
        address _currency
    ) internal returns (uint256) {
        Currency storage currency = campaigns[_campaignId].currencies[
            _currency
        ];
        require(currency.isActive, "DLP Contract: Currency is not active");

        Stake[] storage userStakes = stakes[msg.sender][_campaignId][_currency];

        uint256 totalReward = unclaimedRewards[msg.sender][_campaignId][
            _currency
        ];

        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage stakeEntry = userStakes[i];

            uint256 durationSinceLastClaim;
            uint256 stakingDuration;

            if (block.timestamp > campaigns[_campaignId].campaignEndTime) {
                durationSinceLastClaim = campaigns[_campaignId].campaignEndTime - stakeEntry.lastClaimTime;
                stakeEntry.lastClaimTime = campaigns[_campaignId].campaignEndTime;
                stakingDuration = campaigns[_campaignId].campaignEndTime - stakeEntry.stakeTime;
            } else {
                durationSinceLastClaim = block.timestamp - stakeEntry.lastClaimTime;
                stakeEntry.lastClaimTime = block.timestamp;
                stakingDuration = block.timestamp - stakeEntry.stakeTime;
            }

            totalReward += calculateUserReward(
                msg.sender,
                stakingDuration,
                durationSinceLastClaim,
                _currency,
                currency,
                stakeEntry
            );
        }

        // Reset claimable rewards
        unclaimedRewards[msg.sender][_campaignId][_currency] = 0;

        emit RewardClaimed(
            msg.sender,
            _campaignId,
            _currency,
            totalReward,
            block.timestamp
        );

        return totalReward;
    }

    function _cleanZeroAmountStakes(
        Stake[] storage userStakes
    ) internal {
        uint256 validIndex = 0;
        for (uint256 i = 0; i < userStakes.length; i++) {
            if (userStakes[i].amount > 0) {
                userStakes[validIndex] = userStakes[i];
                validIndex++;
            }
        }
        while (userStakes.length > validIndex) {
            userStakes.pop();
        }
    }

    function addSignatureAdmin(
        address _admin
    ) external onlyAdmin {

        require(featureToggle,"DLP Contract: Feature disabled");
        require(
            _admin != address(0), 
            "DLP Contract: Invalid Address"
        );
        require(
            !signatureAdmin[_admin],
            "DLP Contract: Already added as admin"
        );
        signatureAdmin[_admin] = true;

        emit SignatureAdminAdded(msg.sender, _admin, block.timestamp);
    }

    function removeSignatureAdmin(
        address _admin
    ) external onlyAdmin {

        require(featureToggle,"DLP Contract: Feature disabled");
        require(
            _admin != address(0), 
            "DLP Contract: Invalid Address"
        );
        require(
            signatureAdmin[_admin], 
            "DLP Contract: Not exists!"
        );

        signatureAdmin[_admin] = false;

        emit SignatureAdminRemoved(msg.sender, _admin, block.timestamp);
    }

    function updateCampaignStartTime(
        uint256 _campaignId,
        uint256 _campaignStartTime
    ) external onlyAdmin {
        require(
            _campaignId < campaignCounter,
            "DLP Contract: Campaign does not exist"
        );
        require(
            _campaignStartTime != campaigns[_campaignId].campaignStartTime,
            "DLP Contract: Start time is same"
        );
        require(
            block.timestamp < campaigns[_campaignId].campaignStartTime,
            "DLP Contract: Campaign already started"
        );
        require(
            block.timestamp < _campaignStartTime,
            "DLP Contract: New start time less than current time"
        );
        require(
            _campaignStartTime != 0,
            "DLP Contract: Invalid campaign start time"
        );
        require(
            _campaignStartTime < campaigns[_campaignId].campaignEndTime,
            "DLP Contract: New start time should be less than campaign end time"
        );

        campaigns[_campaignId].campaignStartTime = _campaignStartTime;

        emit CampaignStartTimeUpdated(
            _campaignId,
            _campaignStartTime,
            msg.sender,
            block.timestamp
        );
    }

    function updateCampaignEndTime(
        uint256 _campaignId,
        uint256 _campaignEndTime
    ) external onlyAdmin {
        require(
            _campaignId < campaignCounter,
            "DLP Contract: Campaign does not exist"
        );
        require(
            _campaignEndTime != campaigns[_campaignId].campaignEndTime,
            "DLP Contract: End time is same"
        );
        require(
            block.timestamp < campaigns[_campaignId].campaignEndTime,
            "DLP Contract: Campaign already ended"
        );
        require(
            block.timestamp < _campaignEndTime,
            "DLP Contract: New end time less than current time"
        );
        require(
            _campaignEndTime != 0,
            "DLP Contract: Invalid campaign end time"
        );
        require(
            _campaignEndTime > campaigns[_campaignId].campaignStartTime,
            "DLP Contract: New end time should be greater than campaign start time"
        );

        campaigns[_campaignId].campaignEndTime = _campaignEndTime;

        emit CampaignEndTimeUpdated(
            _campaignId,
            _campaignEndTime,
            msg.sender,
            block.timestamp
        );
    }

    function calculateUserReward(
        address _user,
        uint256 stakingDuration,
        uint256 _durationSinceLastClaim,
        address currencyAddress,
        Currency memory currency,
        Stake memory stakeEntry
    ) internal view returns (uint256 totalReward) {
        uint256 rewardMultiplier;
        if (currencyAddress == nativeCurrency) {
            if (VIPuser[_user]) {
                rewardMultiplier = 3e18; // VIP users get 3x rewards
            } else {
                rewardMultiplier = currency.rewardRatio;
                if (stakingDuration >= 730 days) {
                    rewardMultiplier = (15e17 * rewardMultiplier) / 1e18; // 1:1.5
                } else if (stakingDuration >= 365 days) {
                    rewardMultiplier = (14e17 * rewardMultiplier) / 1e18; // 1:1.4
                } else if (stakingDuration >= 180 days) {
                    rewardMultiplier = (13e17 * rewardMultiplier) / 1e18; // 1:1.3
                } else if (stakingDuration >= 90 days) {
                    rewardMultiplier = (12e17 * rewardMultiplier) / 1e18; // 1:1.2
                }
            }
            // Calculate reward per second based on amount staked
            uint256 rewardPerSecond = (stakeEntry.amount * rewardMultiplier) /
                86400; // 86,400 seconds in 24 hours
            // Calculate total reward for this staking duration
            uint256 reward = (rewardPerSecond * _durationSinceLastClaim) / 1e18;
            totalReward += reward;
        } else {
            uint8 decimals = currency.decimals;

            uint256 stakeAmount = normalizeAmount(stakeEntry.amount, decimals);

            rewardMultiplier = currency.rewardRatio;
            // Calculate reward per second based on amount staked
            uint256 rewardPerSecond = (stakeAmount * rewardMultiplier) / 86400; // 86,400 seconds in 24 hours
            // Calculate total reward for this staking duration
            uint256 reward = (rewardPerSecond * _durationSinceLastClaim) / 1e18;
            totalReward += reward;
        }
    }

    function normalizeAmount(
        uint256 amount,
        uint8 tokenDecimals
    ) internal pure returns (uint256) {
        if (tokenDecimals < 18) {
            return amount * (10 ** (18 - tokenDecimals));
        } else {
            return amount; // No adjustment needed if decimals == 18
        }
    }

    function getUserRewardsForCampaign(
        uint256 _campaignId,
        address _user
    ) public view returns (uint256 totalReward, uint256 _time) {

        require(featureToggle,"DLP Contract: Feature disabled");
        address[] memory currencies = campaigns[_campaignId].currenciesArr;

        for (uint256 index = 0; index < currencies.length; index++) {
            uint256 reward;
            Stake[] storage userStakes = stakes[_user][_campaignId][
                currencies[index]
            ];
            if (userStakes.length > 0) {
                (reward, _time) = getUserRewards(
                    _campaignId,
                    currencies[index],
                    _user
                );
            } else if (
                unclaimedRewards[_user][_campaignId][currencies[index]] > 0
            ) {
                reward = unclaimedRewards[_user][_campaignId][
                    currencies[index]
                ];
                _time = block.timestamp;
            }
            totalReward = totalReward + reward;
        }
    }

    function getUserRewards(
        uint256 _campaignId,
        address _currency,
        address _user
    ) public view returns (uint256 totalReward, uint256 _time) {

        require(featureToggle,"DLP Contract: Feature disabled");

        Currency storage currency = campaigns[_campaignId].currencies[_currency];

        require(currency.isActive, "DLP Contract: Currency is not active");

        Stake[] storage userStakes = stakes[_user][_campaignId][_currency];

        totalReward = unclaimedRewards[_user][_campaignId][_currency];

        for (uint256 i = 0; i < userStakes.length; i++) {
            Stake storage stakeEntry = userStakes[i];

            uint256 durationSinceLastClaim;
            uint256 stakingDuration;

            if (block.timestamp > campaigns[_campaignId].campaignEndTime) {

                durationSinceLastClaim = campaigns[_campaignId].campaignEndTime - stakeEntry.lastClaimTime;
                stakingDuration = campaigns[_campaignId].campaignEndTime - stakeEntry.stakeTime;

            } else {

                durationSinceLastClaim = block.timestamp - stakeEntry.lastClaimTime;
                stakingDuration = block.timestamp - stakeEntry.stakeTime;
            }

            totalReward += calculateUserReward(
                _user,
                stakingDuration,
                durationSinceLastClaim,
                _currency,
                currency,
                stakeEntry
            );
        }

        _time = block.timestamp;
    }

    function getUserCurrenciesStakedInCampaign(
        address _user,
        uint256 _campaignId
    ) public view returns (address[] memory userCurrencies) {
        address[] memory currencies = campaigns[_campaignId].currenciesArr;

        // Create a temporary array in memory with a fixed size
        address[] memory tempCurrencies = new address[](currencies.length);
        uint256 count = 0;

        for (uint256 index = 0; index < currencies.length; index++) {
            Stake[] storage userStakes = stakes[_user][_campaignId][currencies[index]];
            if (userStakes.length > 0) {
                tempCurrencies[count] = currencies[index];
                count++;
            }
        }

        // Create the result array with the exact required size
        userCurrencies = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            userCurrencies[i] = tempCurrencies[i];
        }
    }

    function getUserStakes(
        address _user,
        uint256 _campaignId,
        address _currency
    ) public view returns (Stake[] memory) {
        return stakes[_user][_campaignId][_currency];
    }

    function getCampaignCurrencyDetail(
        uint256 _campaignId,
        address _currency
    ) external view returns (Currency memory) {
        return campaigns[_campaignId].currencies[_currency];
    }

    function getCampaignDetail(
        uint256 _campaignId
    ) public view returns (
        uint256 _campaignStartTime,
        uint256 _campaignEndTime,
        string memory _name,
        address[] memory _currenciesArr
    )
    {
        _campaignStartTime = campaigns[_campaignId].campaignStartTime;
        _campaignEndTime = campaigns[_campaignId].campaignEndTime;
        _name = campaigns[_campaignId].name;
        _currenciesArr = campaigns[_campaignId].currenciesArr;
    }

    function getDLPTokenAddress() public view returns (address) {
        require(featureToggle,"DLP Contract: Feature disabled");
        return DLPToken;
    }

    function getNativeCurrencyAddress() public view returns (address) {
        return nativeCurrency;
    }

    function getVIPUser(address _user) public view returns (bool) {
        require(featureToggle,"DLP Contract: Feature disabled");
        return VIPuser[_user];
    }

    function getUserUnclaimedRewardsForCampaignCurrency(
        address _user,
        uint256 _campaignId,
        address _currency
    ) public view returns (uint256) {
        require(featureToggle,"DLP Contract: Feature disabled");
        return unclaimedRewards[_user][_campaignId][_currency];
    }

    function getSignatureUsed(bytes memory _sig) public view returns (bool) {
        require(featureToggle,"DLP Contract: Feature disabled");
        return usedSignature[_sig];
    }

    function getSignatureAdmin(
        address _adminAddress
    ) public view returns (bool) {
        require(featureToggle,"DLP Contract: Feature disabled");
        return signatureAdmin[_adminAddress];
    }

    function getTxHashStatus(bytes memory _hash) public view returns(bool){
        require(featureToggle,"DLP Contract: Feature disabled");
        return txHashStatus[_hash];
    }

    function getNotConsumedTxHashes(bytes[] memory _hash) public view returns(bytes[] memory notConsumedHashes){
        require(featureToggle,"DLP Contract: Feature disabled");

        bytes[] memory tempHashes = new bytes[](_hash.length);
        uint256 count = 0;

        for (uint256 index = 0; index < _hash.length; index++) {
            if (!txHashStatus[_hash[index]]) {
                tempHashes[count] = _hash[index];
                count++;
            }
        }

        notConsumedHashes = new bytes[](count);

        for (uint256 index = 0; index < count; index++) {
            notConsumedHashes[index] = tempHashes[index];
        }
    }

    function getUserClaimedRewardsForCampaignCurrency(
        address _user,
        uint256 _campaignId,
        address _currency
    ) public view returns (uint256) {
        require(featureToggle,"DLP Contract: Feature disabled");
        return claimedRewards[_user][_campaignId][_currency];
    }

    function getCampaignCounter() public view returns(uint256){
        return campaignCounter;
    }

    function getFeatureToggleStatus() public view returns(bool){
        return featureToggle;
    }

    function getAdminEntriesCounter() public view returns(uint256){
        return adminEntriesCounter;
    }

    function getStandardMessageHash(
        uint256 _campaignId,
        uint256 _salt,
        address _user
    ) public view returns (bytes32 messageHash) {
        messageHash = _hashTypedDataV4(
            keccak256(
                abi.encode(
                    keccak256(
                        "set(uint256 campaignId,uint256 salt,address user)"
                    ),
                    _campaignId,
                    _salt,
                    _user
                )
            )
        );
    }

    function recoverAddress(
        bytes memory _sig,
        bytes32 _msgHash
    ) public pure returns (address) {
        return ECDSAUpgradeable.recover(_msgHash, _sig);
    }

    /**
     * @notice  .
     * @dev     .
     * @return  string  .
     */
    function getProtocolName() public view returns (string memory) {
        return name;
    }
}
