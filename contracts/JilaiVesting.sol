// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./JilaiCrowdSale.sol";

contract JilaiVesting is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    enum Role {
        None,
        Founder,
        User
    }
   
    struct Grant {
        uint256 startTime;
        uint256 amount; // Represents the VESTED amount
        uint256 dexUnlockAmount; // NEW: Represents the DEX unlock portion
        uint256 vestingDuration;
        uint256 monthsClaimed;
        uint256 totalClaimed;
        address recipient;
        Role role;
        uint256 cliffPeriod;
        bool isFounder;
        bool dexUnlockClaimed; // NEW: Flag to check if DEX portion is claimed
    }

    event TokensVested(address indexed beneficiary, uint256 amount);
    event FounderAdded(
        address indexed founder,
        uint256 amount,
        uint256 vestingDuration,
        uint256 lockinPeriod
    );
    event GrantAdded(address indexed recipient);
    event GrantTokensClaimed(
        address indexed recipient,
        uint256 amountClaimed,
        uint256 vestingStartTime,
        uint256 currentTime,
        uint256 elapsedMonths
    );
    event MonthTimeUpdated(uint256 _intervalTime);
    event UpdatedCliffPeriod(uint256 _cliffPeriod);
    event GrantRevoked(
        address recipient,
        uint256 amountVested,
        uint256 amountNotVested
    );
    event WithdrawToken(
        address indexed tokenContract,
        address indexed recipient,
        uint256 amount
    );
    event DexUnlockTokensClaimed(address indexed recipient, uint256 amount);
    event GrantCliffPeriodUpdated(address indexed recipient, uint256 newCliffPeriod);
    event UserCliffPeriodUpdated(uint256 newCliffPeriod);
    event AllTokensClaimed(address indexed recipient, uint256 vestedAmount, uint256 dexUnlockAmount);

    IERC20 public jilaiToken;
    mapping(address => Grant) private tokenGrants;
    mapping(address => Role) public roles;
    address public crowdsale_address;
    uint256 public monthTimeInSeconds;
    uint256 public userCliffPeriod;

    event CrowdsaleAddressUpdated(
        address indexed previousAddress,
        address indexed newAddress
    );
    event VestingStarted(
        address recipient,
        uint256 startTime,
        uint256 saleEndTime
    );

    ///@custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _jilaiToken) public initializer {
        require(_jilaiToken != address(0), "Invalid token address");
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        jilaiToken = IERC20(_jilaiToken);
        monthTimeInSeconds = 2629743 seconds; // Standard month duration
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    modifier onlyCrowdsale() {
        require(
            msg.sender == crowdsale_address,
            "Only crowdsale contract can call this function"
        );
        _;
    }

    /**
     * @notice  function to claim both DEX unlock tokens and vested tokens in one transaction
     */
    function claimAllTokens() external nonReentrant {
        (bool saleEnded, ) = isSaleEnded();
        require(saleEnded, "Sale has not ended yet!");
        
        Grant storage grant = tokenGrants[msg.sender];
        require(grant.amount > 0 || grant.dexUnlockAmount > 0, "No grant exists");
        require(grant.startTime > 0, "Vesting not started");

        uint256 totalToTransfer = 0;
        uint256 dexUnlockClaimed = 0;
        uint256 vestedClaimed = 0;

        // Claim DEX unlock tokens if available and not claimed
        if (grant.dexUnlockAmount > 0 && !grant.dexUnlockClaimed) {
            require(block.timestamp >= grant.startTime + grant.cliffPeriod, "Cliff period has not ended");
            totalToTransfer += grant.dexUnlockAmount;
            dexUnlockClaimed = grant.dexUnlockAmount;
            grant.dexUnlockClaimed = true;
            emit DexUnlockTokensClaimed(msg.sender, grant.dexUnlockAmount);
        }

        // Claim vested tokens if available
        if (grant.amount > 0) {
            require(block.timestamp >= grant.startTime + grant.cliffPeriod, "Cliff period has not ended");
            
            uint256 monthsVested;
            uint256 amountVested;
            (monthsVested, amountVested) = calculateGrantClaim(msg.sender);

            if (amountVested > 0) {
                totalToTransfer += amountVested;
                vestedClaimed = amountVested;
                grant.monthsClaimed += monthsVested;
                grant.totalClaimed += amountVested;
                emit GrantTokensClaimed(
                    msg.sender,
                    amountVested,
                    grant.startTime,
                    block.timestamp,
                    monthsVested
                );
            }
        }

        require(totalToTransfer > 0, "No tokens available to claim");
        jilaiToken.safeTransfer(msg.sender, totalToTransfer);
        
        emit AllTokensClaimed(msg.sender, vestedClaimed, dexUnlockClaimed);
    }

    // // Keep individual claim functions for backward compatibility
    // function claimDexUnlockTokens() external nonReentrant {
    //     Grant storage grant = tokenGrants[msg.sender];
    //     require(grant.dexUnlockAmount > 0, "No DEX unlock tokens available");
    //     require(!grant.dexUnlockClaimed, "DEX unlock tokens already claimed");
    //     require(grant.startTime > 0, "Sale has not ended yet");
    //     require(block.timestamp >= grant.startTime + grant.cliffPeriod, "Cliff period has not ended");

    //     grant.dexUnlockClaimed = true;
    //     uint256 amountToClaim = grant.dexUnlockAmount;

    //     jilaiToken.safeTransfer(msg.sender, amountToClaim);
    //     emit DexUnlockTokensClaimed(msg.sender, amountToClaim);
    // }

    // function claimVestedTokens() external nonReentrant {
    //     (bool saleEnded, ) = isSaleEnded();
    //     require(saleEnded, "Sale has not ended yet!");
    //     Grant storage grant = tokenGrants[msg.sender];

    //     require(grant.amount > 0, "No grant exists");
    //     require(grant.startTime > 0, "Vesting not started");
    //     require(block.timestamp >= grant.startTime + grant.cliffPeriod, "Cliff period has not ended");
        
    //     uint256 monthsVested;
    //     uint256 amountVested;
    //     (monthsVested, amountVested) = calculateGrantClaim(msg.sender);

    //     require(amountVested > 0, "No tokens vested");

    //     grant.monthsClaimed += monthsVested;
    //     grant.totalClaimed += amountVested;

    //     jilaiToken.safeTransfer(msg.sender, amountVested);
    //     emit GrantTokensClaimed(
    //         msg.sender,
    //         amountVested,
    //         grant.startTime,
    //         block.timestamp,
    //         monthsVested
    //     );
    // }

    function calculateGrantClaim(
        address _recipient
    ) public view returns (uint256, uint256) {
        Grant storage grant = tokenGrants[_recipient];
        (bool saleEnded, ) = isSaleEnded();

        if (!saleEnded || grant.startTime == 0) {
            return (0, 0);
        }

        uint256 vestingBeginsTime = grant.startTime + grant.cliffPeriod;

        // before cliff ends → nothing vested
        if (block.timestamp < vestingBeginsTime) {
            return (0, 0);
        }

        // elapsed full months since vesting began
        uint256 elapsedMonths = (block.timestamp - vestingBeginsTime) / monthTimeInSeconds;

        // cap at full duration
        if (elapsedMonths > grant.vestingDuration) {
            elapsedMonths = grant.vestingDuration;
        }

        // nothing new vested yet
        if (elapsedMonths <= grant.monthsClaimed) {
            return (0, 0);
        }

        uint256 monthsVested = elapsedMonths - grant.monthsClaimed;

        // if fully vested
        if (grant.monthsClaimed + monthsVested >= grant.vestingDuration) {
            uint256 remainingGrant = grant.amount - grant.totalClaimed;
            return (grant.vestingDuration - grant.monthsClaimed, remainingGrant);
        }

        // normal vesting amount
        uint256 amountVested = (grant.amount * monthsVested) / grant.vestingDuration;

        return (monthsVested, amountVested);
    }

    function addCrowdsaleAddress(
        address newCrowdsaleAddress
    ) external onlyOwner {
        require(newCrowdsaleAddress != address(0), "Invalid address");
        address previousCrowdsaleAddress = crowdsale_address;
        crowdsale_address = newCrowdsaleAddress;
        emit CrowdsaleAddressUpdated(
            previousCrowdsaleAddress,
            newCrowdsaleAddress
        );
    }

    // Fetch vestingMonths from JilaiCrowdSale
    function getVestingMonths() public view returns (uint256) {
        require(crowdsale_address != address(0), "Crowdsale address not set");
        JilaiCrowdSale crowdsale = JilaiCrowdSale(crowdsale_address);
        return crowdsale.vestingMonths();
    }

    function isSaleEnded() public view returns (bool, uint256) {
        JilaiCrowdSale crowdsale = JilaiCrowdSale(crowdsale_address);
        return (crowdsale.isFinalized(), crowdsale.getSaleEndTime());
    }

    function addTokenGrant(
        address _recipient,
        uint256 _vestingAmount,
        uint256 _dexUnlockAmount,
        bool _isFounder
    ) external nonReentrant onlyCrowdsale {
        require(_recipient != address(0), "Invalid recipient address");
        require(_vestingAmount > 0 || _dexUnlockAmount > 0, "Amount must be greater than 0");
        require(
            !tokenGrants[_recipient].isFounder && !_isFounder,
            "Founder can't able to participate."
        );

        uint256 vestingDuration = getVestingMonths();
        require(vestingDuration > 0, "Vesting months not set in crowdsale");

        Grant storage grant = tokenGrants[_recipient];

        if (grant.amount == 0 && grant.dexUnlockAmount == 0) {
            // First time grant
            tokenGrants[_recipient] = Grant({
                startTime: 0,
                amount: _vestingAmount,
                dexUnlockAmount: _dexUnlockAmount,
                vestingDuration: vestingDuration,
                monthsClaimed: 0,
                totalClaimed: 0,
                recipient: _recipient,
                role: Role.User,
                cliffPeriod: userCliffPeriod,
                isFounder: _isFounder,
                dexUnlockClaimed: false
            });
        } else {
            // For additional purchases, add to the total amounts
            grant.amount += _vestingAmount;
            grant.dexUnlockAmount += _dexUnlockAmount;
        }

        roles[_recipient] = Role.User;
        emit GrantAdded(_recipient);
    }

    function updateGrantCliffPeriod(address _recipient, uint256 _newCliffPeriod) external onlyOwner {
        Grant storage grant = tokenGrants[_recipient];
        require(grant.amount > 0 || grant.dexUnlockAmount > 0, "No grant exists for recipient");
        grant.cliffPeriod = _newCliffPeriod;
        emit GrantCliffPeriodUpdated(_recipient, _newCliffPeriod);
    }
    
    function setUserCliffPeriod(uint256 _newCliffPeriod) external onlyOwner {
        require(_newCliffPeriod > 0, "Cliff period must be greater than 0");
        userCliffPeriod = _newCliffPeriod;
        emit UserCliffPeriodUpdated(_newCliffPeriod);
    }

    function updateMonthsTime(
        uint256 _intervalTime
    ) external onlyOwner nonReentrant {
        require(_intervalTime > 0, "Interval time must be greater than 0");
        monthTimeInSeconds = _intervalTime;
        emit MonthTimeUpdated(monthTimeInSeconds);
    }

    function currentTime() private view returns (uint256) {
        return block.timestamp;
    }

    function addFounder(
        address _founder,
        uint256 _amount,
        uint256 _vestingDuration,
        uint256 _lockInPeriod
    ) external onlyOwner nonReentrant {
        require(_founder != address(0), "Invalid Founder Address");
        require(_amount > 0, "Amount must be greater than 0");
        require(_vestingDuration > 0, "Vesting Duration greater than 0");
        require(roles[_founder] == Role.None, "Address already has a role");
        require(tokenGrants[_founder].amount == 0, "Grant already exists");

        uint256 amountVestedPerMonth = _amount / _vestingDuration;
        require(amountVestedPerMonth > 0, "Amount too small for Vesting");

        tokenGrants[_founder] = Grant({
            startTime: currentTime() + _lockInPeriod + monthTimeInSeconds,
            amount: _amount,
            vestingDuration: _vestingDuration,
            monthsClaimed: 0,
            totalClaimed: 0,
            recipient: _founder,
            role: Role.Founder,
            cliffPeriod: _lockInPeriod,
            isFounder: true,
            dexUnlockAmount:0,
            dexUnlockClaimed:false
        });

        roles[_founder] = Role.Founder;

        emit FounderAdded(_founder, _amount, _vestingDuration, _lockInPeriod);
    }

    function isFounder(address founder) external view returns (bool) {
        Grant storage tokenGrant = tokenGrants[founder];
        return tokenGrant.isFounder;
    }

    function getGrantDetails(
        address _recipient
    )
        external
        view
        returns (
            uint256 amount,
            uint256 vestingDuration,
            uint256 saleEndTime,
            uint256 monthsClaimed,
            uint256 totalClaimed,
            uint256 remainingAmount,
            uint256 nextClaim,
            Role role,
            uint256 cliffPeriod,
            uint256 vestingStartTime,
            uint256 dexUnlockAmount,
            bool dexUnlockClaimed
        )
    {
        Grant storage grant = tokenGrants[_recipient];
        require(grant.amount > 0 || grant.dexUnlockAmount > 0, "Grant does not exist");

        uint256 _nextClaim = 0;
        uint256 vestingBeginsTime = 0;

        if (grant.startTime != 0 && grant.totalClaimed < grant.amount) {
            vestingBeginsTime = grant.startTime + grant.cliffPeriod;
            uint256 finalDate = vestingBeginsTime + (grant.vestingDuration * monthTimeInSeconds);

            if (block.timestamp < vestingBeginsTime) {
                _nextClaim = vestingBeginsTime; // waiting for cliff to end
            } else if (block.timestamp < finalDate) {
                uint256 intervalsSinceStart = (block.timestamp - vestingBeginsTime) / monthTimeInSeconds;
                _nextClaim = vestingBeginsTime + ((intervalsSinceStart + 1) * monthTimeInSeconds);
            }
        }

        return (
            grant.amount,
            grant.vestingDuration,
            grant.startTime,
            grant.monthsClaimed,
            grant.totalClaimed,
            grant.amount - grant.totalClaimed,
            _nextClaim,
            grant.role,
            grant.cliffPeriod,
            vestingBeginsTime,
            grant.dexUnlockAmount,
            grant.dexUnlockClaimed
        );
    }

    function isVestingComplete(
        address _recipient
    ) external view returns (bool) {
        Grant storage grant = tokenGrants[_recipient];
        return grant.totalClaimed >= grant.amount && grant.amount > 0;
    }

    function getRole(address user) external view returns (Role) {
        require(user != address(0), "Invalid user address");
        return roles[user];
    }

    function getVestingTiming(
        address _recipient
    )
        external
        view
        returns (
            uint256 cliffEndTime,
            uint256 currenttime,
            uint256 elapsedTime,
            uint256 elapsedMonths,
            bool vestingStarted
        )
    {
        Grant storage grant = tokenGrants[_recipient];
        if (grant.amount == 0 && grant.dexUnlockAmount == 0) return (0, 0, 0, 0, false);

        currenttime = block.timestamp;
        cliffEndTime = grant.startTime + grant.cliffPeriod;

        vestingStarted = currenttime >= cliffEndTime;

        if (vestingStarted) {
            elapsedTime = currenttime - cliffEndTime;
            elapsedMonths = elapsedTime / monthTimeInSeconds;
        }

        return (cliffEndTime, currenttime, elapsedTime, elapsedMonths, vestingStarted);
    }

    function setGrantStartTime(
        address _recipient,
        uint256 _startTime
    ) external onlyCrowdsale {
        require(_recipient != address(0), "Invalid recipient address");
        require(_startTime > 0, "Invalid start time");
        Grant storage grant = tokenGrants[_recipient];
        require(grant.amount > 0 || grant.dexUnlockAmount > 0, "No grant exists");
        grant.startTime = _startTime;
        emit VestingStarted(_recipient, _startTime, _startTime);
    }

    function withdrawToken(
        address _tokenContract,
        uint256 _amount
    ) external onlyOwner nonReentrant {
        require(_tokenContract != address(0), "Address cant be zero address");
        IERC20 tokenContract = IERC20(_tokenContract);
        tokenContract.safeTransfer(msg.sender, _amount);
        emit WithdrawToken(_tokenContract, msg.sender, _amount);
    }
}