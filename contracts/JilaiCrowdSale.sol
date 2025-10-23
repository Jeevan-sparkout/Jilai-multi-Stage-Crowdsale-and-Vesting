// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./JilaiVesting.sol";
import "./jilaiPromoLibrary.sol";

/**
 * @title JilaiCrowdSale
 * @notice A crowdsale contract for Jilai tokens in exchange for ETH across multiple stages
 * @dev Implements stage-based pricing, DEX unlock, vesting, token forwarding and promo codes using OpenZeppelin upgradeable contracts
 */
contract JilaiCrowdSale is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    PausableUpgradeable
{
    IERC20 public jilaiToken;
    JilaiVesting public vestingContract;
    uint256 public vestingMonths;

    using SafeERC20 for IERC20;
    using JilaiPromoLibrary for JilaiPromoLibrary.PromoStorage;

    struct UserInfo {
        uint256 ethContributed;
        uint256 jilaiReceived;
        uint256 dexUnlockedTokens;
        uint256 vestedTokens;
        string[] usedPromoCodes; // Track promo codes used by user
    }

    struct Stage {
        uint256 rate; // Price in USD with 8 decimals per Jilai token
        uint256 tokensForSale; // Total tokens available in stage (18 decimals)
        uint256 dexUnlockPercent; // Percentage of tokens unlocked immediately
        uint256 tokensSold; // Number of tokens sold in stage (18 decimals)
    }

    mapping(address => UserInfo) public users;
    mapping(address => uint256) public investments; //Tracks ETH Contibutions in wei
    address[] public buyers;

    Stage[] public stages;
    uint256 public currentStage;
    uint256 public totalTokensSold;
    bool public isFinalized;
    uint256 public saleEndTime;
    uint256 private constant MINIMUM_TOKEN_AMOUNT = 1 * 10 ** 18;
    AggregatorV3Interface public priceFeed;

    // Promo code storage - made internal and added getters
    JilaiPromoLibrary.PromoStorage internal promoStorage;

    event TokensPurchased(
        address indexed buyer,
        uint256 indexed totalAmount,
        uint256 indexed dexUnlockedAmount,
        uint256 vestedAmount,
        uint256 ethRefunded,
        string promoCode
    );
    event WithdrawToken(
        address indexed tokenContract,
        address indexed recipient,
        uint256 amount
    );
    event StageAdvanced(uint256 indexed newStage);
    event StageUpdated(
        uint256 indexed stageIndex,
        uint256 rate,
        uint256 tokensForSale,
        uint256 dexUnlockPercent
    );
    event RewardTokenUpdated(address indexed newTokenAddress);
    event AutoTokensAdded(uint256 _stageIndex, uint256 requiredTokens);
    event Finalized();
    event SaleEnded(uint256 indexed endTime);
    event TokensForwarded(
        uint256 indexed fromStage,
        uint256 indexed toStageOrOwner,
        uint256 amount
    );
    event PriceFeedUpdated(address indexed newPriceFeedAddress);
    event PromoCodeAdded(string  promoCode , string  description , uint8  promoCodeType, uint256  value, uint256  expiration);
    event PromoCodeUpdated(string  oldCode, string  newCode , string  updatedDescription , uint8 updatedPromoCodeType , uint256  updatedValue , uint256 updatedExpiration);
    event PromoCodeDeactivated(string  promoCode);
    event PromoCodeApplied(address indexed user, string  promoCode,string  description, uint8 promoCodeType,uint256  value ,uint256 expiration,  uint256 tokenAmount);

    /**
     * @dev Modifier to make a function callable only while the sale is open.
     */
    modifier onlyWhileOpen() {
        require(!isFinalized, "Sale is finalized");
        require(currentStage < stages.length, "All stages completed");
        _;
    }

    /**
     * @notice Disables initializers to prevent contract from being initialized again.
     * @custom:oz-upgrades-unsafe-allow constructor
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Authorizes an upgrade to a new contract implementation.
     * @dev Restricted to only the contract owner.
     * @param newImplementation Address of the new implementation contract.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function initialize(
        address _jilaiToken,
        address _vestingContract,
        address _priceFeed
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();
        __Pausable_init();

        require(_jilaiToken != address(0), "Invalid Jilai Token Address!");
        require(
            _vestingContract != address(0),
            "Invalid Vesting Contract Address"
        );
        require(_priceFeed != address(0), "Invalid Price Feed Address");

        jilaiToken = IERC20(_jilaiToken);
        vestingContract = JilaiVesting(_vestingContract);
        vestingMonths = 36; // Default vesting period is 36 months
        priceFeed = AggregatorV3Interface(_priceFeed);

        // 12 stages with adjusted prices
        stages.push(Stage(5000000, 120000000 * 10 ** 18, 30, 0)); // Stage 1 ($0.05)
        stages.push(Stage(7000000, 110000000 * 10 ** 18, 32, 0)); // Stage 2 ($0.07)
        stages.push(Stage(9000000, 100000000 * 10 ** 18, 34, 0)); // Stage 3 ($0.09)
        stages.push(Stage(11000000, 100000000 * 10 ** 18, 36, 0)); // Stage 4 ($0.11)
        stages.push(Stage(13000000, 100000000 * 10 ** 18, 38, 0)); // Stage 5 ($0.13)
        stages.push(Stage(16000000, 90000000 * 10 ** 18, 40, 0)); // Stage 6 ($0.16)
        stages.push(Stage(18000000, 90000000 * 10 ** 18, 42, 0)); // Stage 7 ($0.18)
        stages.push(Stage(21000000, 90000000 * 10 ** 18, 44, 0)); // Stage 8 ($0.21)
        stages.push(Stage(24000000, 90000000 * 10 ** 18, 46, 0)); // Stage 9 ($0.24)
        stages.push(Stage(27000000, 70000000 * 10 ** 18, 48, 0)); // Stage 10 ($0.27)
        stages.push(Stage(30000000, 70000000 * 10 ** 18, 50, 0)); // Stage 11 ($0.300)
        stages.push(Stage(33000000, 70000000 * 10 ** 18, 52, 0)); // Stage 12 ($0.330)

        currentStage = 0; // Start at Stage 1 (index 0)
    }
    /**
     * @notice Allows a user to buy Jilai tokens using ETH with optional promo code
     * @param _promoCode The promo code to apply for discount (empty string for no promo)
     */
    function buyTokens(string memory _promoCode)
        external
        payable
        nonReentrant
        whenNotPaused
    {   
        require(!isFinalized, "Sale finalized");
        require(currentStage < stages.length, "All stages completed");
        
        uint256 ethAmount = msg.value;
        require(ethAmount > 0, "ETH > 0");
        
        Stage storage stage = stages[currentStage];
        
        // Get price data ONCE at the beginning
        (, int256 price, , ,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed data");
        uint256 ethUsdPrice = uint256(price);
        
        // Calculate base token amount
        uint256 usdAmount = (ethAmount * ethUsdPrice) / 10 ** 18;
        uint256 baseTokenAmount = usdAmount * 10 ** 18 / stage.rate;
        require(baseTokenAmount > 0, "Tokens > 0");

        // Apply promo code ONCE and store results
        uint256 finalTokenAmount = baseTokenAmount;
        uint256 effectiveRate = stage.rate;
        bool hasPromo = bytes(_promoCode).length > 0;
        JilaiPromoLibrary.PromoCode memory promo;
        
        if (hasPromo) {
            promo = promoStorage.getPromoCode(_promoCode);
            require(promo.isActive && promo.expiration > block.timestamp, "Invalid or expired promo code");
            
            if (promo.promoType == 0) {
                // Type 0: FixedPrice - recalculate with promo rate
                finalTokenAmount = usdAmount * 10 ** 18 / promo.value;
                effectiveRate = promo.value;
            } else {
                // Type 1: BonusPercent - apply bonus to base amount
                finalTokenAmount = baseTokenAmount * (10000 + promo.value) / 10000;
            }
            
            // Track promo usage (ONCE)
            promoStorage.applyPromoCode(_promoCode, finalTokenAmount, stage.rate);
            
            emit PromoCodeApplied(
                msg.sender, 
                promo.code,
                promo.description,
                promo.promoType,
                promo.value,
                promo.expiration,
                finalTokenAmount
            );
        }

        // Calculate actual purchase with the final token amount
        (uint256 _tokenAmount, uint256 ethUsed, uint256 ethRefunded) = _calculatePurchase(
            finalTokenAmount,
            ethAmount,
            effectiveRate,
            hasPromo,  // Pass boolean instead of string
            hasPromo ? promo : JilaiPromoLibrary.PromoCode("", "", 0, 0, 0, false), // Pass promo or empty
            ethUsdPrice  // Pass the price we already fetched
        );

        require(jilaiToken.balanceOf(address(this)) >= _tokenAmount, "Insufficient Tokens");

        uint256 dexUnlockAmount = (_tokenAmount * stage.dexUnlockPercent) / 100;
        uint256 vestingAmount = _tokenAmount - dexUnlockAmount;

        stage.tokensSold += _tokenAmount;
        totalTokensSold += _tokenAmount;

        UserInfo storage user = users[msg.sender];
        if (user.ethContributed == 0) {
            buyers.push(msg.sender);
        }
        user.ethContributed += ethUsed;
        user.jilaiReceived += _tokenAmount;
        user.dexUnlockedTokens += dexUnlockAmount;
        user.vestedTokens += vestingAmount;
        investments[msg.sender] += ethUsed;

        // Track promo code usage
        if (hasPromo) {
            user.usedPromoCodes.push(_promoCode);
        }

        // Transfer ALL tokens to vesting contract (both DEX unlock and vested)
        jilaiToken.safeTransfer(address(vestingContract), _tokenAmount);
        
        // Call addTokenGrant with both vested and DEX unlock amounts
        vestingContract.addTokenGrant(msg.sender, vestingAmount, dexUnlockAmount, false);

        // Refund excess ETH
        if (ethRefunded > 0) {
            (bool success,) = msg.sender.call{value: ethRefunded}("");
            require(success, "ETH transfer failed");
        }

        emit TokensPurchased(msg.sender, _tokenAmount, dexUnlockAmount, vestingAmount, ethRefunded, _promoCode);

        // Finalize automatically if all tokens sold in stage
        if (stage.tokensSold >= stage.tokensForSale) {
            _finalizeStage();
        }
    }

    /**
     * @notice Calculate token purchase considering stage limits
     */
    function _calculatePurchase(
        uint256 tokenAmount,
        uint256 ethAmount,
        uint256 effectiveRate,
        bool hasPromo,
        JilaiPromoLibrary.PromoCode memory promo,
        uint256 ethUsdPrice  // Use pre-fetched price
    ) internal view returns (uint256 _tokenAmount, uint256 ethUsed, uint256 ethRefunded) {
        Stage storage stage = stages[currentStage];
        uint256 remainingTokens = stage.tokensForSale - stage.tokensSold;
        
        _tokenAmount = tokenAmount;
        ethUsed = ethAmount;
        ethRefunded = 0;
        
        if (_tokenAmount > remainingTokens) {
            _tokenAmount = remainingTokens;
            
            uint256 usdAmount;
            
            if (hasPromo) {
                if (promo.promoType == 0) {
                    // Type 0: FixedPrice - use effectiveRate directly
                    usdAmount = (_tokenAmount * effectiveRate) / 10 ** 18;
                } else {
                    // Type 1: BonusPercent - need to calculate base tokens first
                    uint256 baseTokens = _tokenAmount * 10000 / (10000 + promo.value);
                    usdAmount = (baseTokens * stage.rate) / 10 ** 18;
                }
            } else {
                // No promo - use stage rate
                usdAmount = (_tokenAmount * stage.rate) / 10 ** 18;
            }
            
            ethUsed = (usdAmount * 10 ** 18) / ethUsdPrice;
            ethRefunded = ethAmount - ethUsed;
        }
        
        return (_tokenAmount, ethUsed, ethRefunded);
    }

    /**
     * @notice Get base token amount without promo codes (view function)
     */
    function _getBaseTokenAmount(uint256 ethAmount) public view returns (uint256) {
        require(ethAmount >= 10000000000000, "ETH amount too low");
        
        (, int256 price, , ,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price feed data");
        uint256 ethUsdPrice = uint256(price);
        
        Stage storage stage = stages[currentStage];
        uint256 usdAmount = (ethAmount * ethUsdPrice) / 10 ** 18;
        return usdAmount * 10 ** 18 / stage.rate;
    }
        

    /**
     * @notice Public view function to preview token amount with promo
     */
    function getTokenAmount(uint256 ethAmount, string memory _promoCode) public view returns (uint256) {
        require(ethAmount >= 10000000000000, "ETH amount too low");
        require(!isFinalized, "Sale is finalized");
        require(currentStage < stages.length, "All stages completed");
        
        uint256 baseTokenAmount = _getBaseTokenAmount(ethAmount);
        
        if (bytes(_promoCode).length > 0) {
            JilaiPromoLibrary.PromoCode memory promo = promoStorage.getPromoCode(_promoCode);
            require(promo.isActive && promo.expiration > block.timestamp, "Invalid or expired promo code");
            
            if (promo.promoType == 0) {
                // Type 0: FixedPrice
                (, int256 price, , ,) = priceFeed.latestRoundData();
                require(price > 0, "Invalid price feed data");
                uint256 ethUsdPrice = uint256(price);
                uint256 usdAmount = (ethAmount * ethUsdPrice) / 10 ** 18;
                return usdAmount * 10 ** 18 / promo.value;
            } else {
                // Type 1: BonusPercent
                return baseTokenAmount * (10000 + promo.value) / 10000;
            }
        }
        
        return baseTokenAmount;
    }
    /**
     * @notice Finalize current stage and advance or end sale
     */
    function _finalizeStage() internal {
        Stage storage stage = stages[currentStage];
        uint256 remainingTokens = stage.tokensForSale - stage.tokensSold;
        
        if (remainingTokens > 0) {
            if (currentStage < stages.length - 1) {
                stages[currentStage + 1].tokensForSale += remainingTokens;
                emit TokensForwarded(currentStage, currentStage + 1, remainingTokens);
            } else {
                jilaiToken.safeTransfer(owner(), remainingTokens);
                emit TokensForwarded(currentStage, 0, remainingTokens);
            }
        }
        
        stage.tokensSold = stage.tokensForSale;
        
        if (currentStage < stages.length - 1) {
            currentStage++;
            emit StageAdvanced(currentStage);
        } else {
            isFinalized = true;
            saleEndTime = block.timestamp;
            _handleSaleEnd();
        }
    }

    function _handleSaleEnd() private {
        for (uint256 i = 0; i < buyers.length; i++) {
            address buyer = buyers[i];
            if (users[buyer].vestedTokens > 0) {
                vestingContract.setGrantStartTime(
                    buyer,
                    saleEndTime 
                );
            }
        }

        uint256 remainingTokens = jilaiToken.balanceOf(address(this));
        if (remainingTokens > 0) {
            jilaiToken.safeTransfer(owner(), remainingTokens);
            emit TokensForwarded(currentStage, 0, remainingTokens);
        }

        emit Finalized();
        emit SaleEnded(saleEndTime);
    }

    // Promo Code Management Functions

    /**
     * @notice Add a new promo code
     * @param _code The promo code string
     * @param _description Description of the promo
     * @param _promoType 0 for FixedPrice, 1 for BonusPercent
     * @param _value Value for the promo (price for FixedPrice, percentage for BonusPercent)
     * @param _expiration Expiration timestamp
     */
    function addPromoCode(
        string memory _code,
        string memory _description,
        uint8 _promoType,
        uint256 _value,
        uint256 _expiration
    ) external onlyOwner {
        promoStorage.addPromoCode(_code, _description, _promoType, _value, _expiration);
        
        emit PromoCodeAdded(
        _code,
        _description,
        _promoType,
        _value,
        _expiration);
    }

    /**
     * @notice Update an existing promo code
     * @param _code The new promo code string
     * @param _description Description of the promo
     * @param _promoType 0 for FixedPrice, 1 for BonusPercent
     * @param _value Value for the promo
     * @param _expiration Expiration timestamp
     * @param _oldCode The old promo code to update
     */
    function updatePromoCode(
        string memory _code,
        string memory _oldCode,
        string memory _description,
        uint8 _promoType,
        uint256 _value,
        uint256 _expiration
            ) external onlyOwner {
        promoStorage.updatePromoCode(_code, _description, _promoType, _value, _expiration, _oldCode);
        emit PromoCodeUpdated(
            _oldCode, 
            _code , 
            _description,
            _promoType,
            _value,
            _expiration
            );
            
    }

    /**
     * @notice Deactivate a promo code
     * @param _code The promo code to deactivate
     */
    function deactivatePromoCode(string memory _code) external onlyOwner {
        promoStorage.deactivatePromoCode(_code);
        emit PromoCodeDeactivated(_code);
    }

    /**
     * @notice Get promo code usage history for a user
     * @param _user User address
     * @param _code Promo code
     * @return Usage count
     */
    function getPromoHistory(address _user, string memory _code) external view returns (uint256) {
        return promoStorage.getPromoHistory(_user, _code);
    }

    /**
     * @notice Get promo code details
     * @param _code Promo code to query
     * @return code The promo code string
     * @return description Description of the promo
     * @return promoType 0 for FixedPrice, 1 for BonusPercent
     * @return value Value of the promo
     * @return expiration Expiration timestamp
     * @return isActive Whether the promo code is active
     */
    function getPromoCode(string memory _code) external view returns (
        string memory code,
        string memory description,
        uint8 promoType,
        uint256 value,
        uint256 expiration,
        bool isActive
    ) {
        JilaiPromoLibrary.PromoCode memory promo = promoStorage.getPromoCode(_code);
        return (
            promo.code,
            promo.description,
            promo.promoType,
            promo.value,
            promo.expiration,
            promo.isActive
        );
    }

    /**
     * @notice Check if a promo code is valid and active
     * @param _code Promo code to check
     * @return isValid True if the promo code is valid and active
     */
    function isPromoCodeValid(string memory _code) external view returns (bool) {
        return promoStorage.isPromoCodeValid(_code);
    }

    /**
     * @notice Get promo codes used by a user
     * @param _user User address
     * @return Array of promo codes used
     */
    function getUserPromoCodes(address _user) external view returns (string[] memory) {
        return users[_user].usedPromoCodes;
    }

    // Existing functions

    function finalize() external onlyOwner {
        require(!isFinalized, "Sale Already Finalized!");
        require(currentStage >= stages.length - 1, "Not all stages completed!");

        isFinalized = true;
        saleEndTime = block.timestamp;
        _handleSaleEnd();
    }

    function _changeVestingInMonths(uint256 vestingInMonths) internal virtual {
        vestingMonths = vestingInMonths;
    }

    function getVestingMonths() public view returns (uint256) {
        return vestingMonths;
    }

    function getSaleEndTime() public view returns (uint256) {
        return saleEndTime;
    }

    function isSaleEnded() public view returns (bool, uint256) {
        return (isFinalized, saleEndTime);
    }

    function changeVestingInMonths(
        uint256 vestingInMonths
    ) external virtual onlyOwner onlyWhileOpen whenNotPaused {
        require(vestingInMonths > 0, "vestingInMonths cannot be 0");
        _changeVestingInMonths(vestingInMonths);
    }

    function pauseContract() external virtual onlyOwner {
        _pause();
    }

    function unPauseContract() external virtual onlyOwner {
        _unpause();
    }

    function getCurrentStageDetails() external view returns (Stage memory) {
        return stages[currentStage];
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

    function withdrawETH() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No ETH to Withdraw!");
        (bool success, ) = owner().call{value: balance}("");
        require(success, "ETH Transfer Failed!");
    }

    function setRewardToken(address _newJilaiToken) external onlyOwner {
        require(_newJilaiToken != address(0), "Invalid Token Address!");
        require(_newJilaiToken != address(jilaiToken), "Same Token Address");
        jilaiToken = IERC20(_newJilaiToken);
        emit RewardTokenUpdated(_newJilaiToken);
    }

    function getRewardToken() external view returns (address) {
        return address(jilaiToken);
    }

    function stopSale() external onlyOwner {
        require(!isFinalized, "Sale Already Finalized!");
        isFinalized = true;
        saleEndTime = block.timestamp;
        _handleSaleEnd();
    }

    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function setPriceFeed(address _newPriceFeed) external onlyOwner {
        require(_newPriceFeed != address(0), "Invalid Price Feed Address");
        require(_newPriceFeed != address(priceFeed), "Same Price Feed Address");
        priceFeed = AggregatorV3Interface(_newPriceFeed);
        emit PriceFeedUpdated(_newPriceFeed);
    }

    function updateTokensSold(uint256 _stageIndex, uint256 _tokensSold) external onlyOwner {
        require(_stageIndex < stages.length, "Invalid stage index");
        require(_tokensSold <= stages[_stageIndex].tokensForSale, "Tokens sold cannot exceed tokens for sale");
        totalTokensSold = totalTokensSold - stages[_stageIndex].tokensSold + _tokensSold;
        stages[_stageIndex].tokensSold = _tokensSold;
    }

    function updateStage(
        uint256 _stageIndex,
        uint256 _rate,
        uint256 _tokensForSale,
        uint256 _dexUnlockPercent
    ) external onlyOwner {
        require(_stageIndex < stages.length, "Invalid stage index");
        require(_rate > 0, "Rate must be greater than 0");
        require(_tokensForSale > 0, "Tokens For sale must be greater than 0");
        require(
            _dexUnlockPercent > 0 && _dexUnlockPercent <= 100,
            "Invalid DEX unlock Percentage"
        );

        Stage storage stage = stages[_stageIndex];
        stage.rate = _rate;
        stage.tokensForSale = _tokensForSale;
        stage.dexUnlockPercent = _dexUnlockPercent;

        emit StageUpdated(
            _stageIndex,
            _rate,
            _tokensForSale,
            _dexUnlockPercent
        );
    }
}