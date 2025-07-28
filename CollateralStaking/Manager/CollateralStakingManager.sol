pragma solidity ^0.5.16;

import "./CollateralStakingManagerInterface.sol";
import "../Mediator/CollateralStakingMediatorProxy.sol";
import "../Mediator/CollateralStakingMediatorInterface.sol";
import "../../CErc721/CErc721Staking/CErc721StakingInterface.sol";
import "../../CErc20/CErc20Staking/CErc20StakingInterface.sol";
import "../../CErc20/CEtherStaking/CEtherStakingInterface.sol";
import "../../Interface/EIP20Interface.sol";
import "../../Lib/Math/SafeMath.sol";
import "../../Lib/SafeErc20/SafeErc20.sol";

/**
 * @title MetaLend's CollateralStakingManager Contract
 * @notice Manages staking of collateral to official onchain staking contracts to accrue rewards
 * @author MetaLend
 */
contract CollateralStakingManager is CollateralStakingManagerInterface {
    using SafeMath for uint256;
    
    /**
     * @notice Construct a new CErc721 money market
     * @param royaltiesReceiver_ of the royalties receiver from rewards
     * @param collateralStakingMediatorImplementation_ of the staking mediator implementation for proxies
     * @param rewardsRoyaltiesPercentage_ percentage of the rewards royalties, scale 0 <=> 10000, 1% = 100
     */
    function initialize(
        address payable royaltiesReceiver_,
        address collateralStakingMediatorImplementation_,
        uint rewardsRoyaltiesPercentage_
    ) public {
        require(msg.sender == admin, "Only admin may initialize the manager");
        require(
            CollateralStakingMediatorInterface(collateralStakingMediatorImplementation_)
                .isCollateralStakingMediator(), "Not a mediator implementation"
        );
        require(royaltiesReceiver_ != address(0), "royalties receiver cannot be zero address");
        require(rewardsRoyaltiesPercentage_ <= feeDenominator(), "Percentage overflow");

        royaltiesReceiver = royaltiesReceiver_;
        collateralStakingMediatorImplementation = collateralStakingMediatorImplementation_;
        rewardsRoyaltiesPercentage = rewardsRoyaltiesPercentage_;
        emit NewRoyaltiesReceiver(royaltiesReceiver_, address(0));
        emit NewCollateralStakingMediatorImplementation(collateralStakingMediatorImplementation_, address(0));
        emit NewRewardsRoyaltiesPercentage(rewardsRoyaltiesPercentage_, 0);
    }

    /**
     * @notice get user's staking mediator contract proxy
     * @param user of the user who stakes collateral
     */
    function getCollateralStakingMediator(address user) external view returns(address) {
        return userCollateralMediator[user];
    }

    /**
     * @notice get or create user's staking mediator contract proxy
     * @dev tries to get, if user does not have one, create a new mediator
     * @param user of the user who stakes collateral
     */
    function getOrCreateCollateralStakingMediator(address payable user) external returns(address) {
        require(cErcStakingMarket[msg.sender] || (msg.sender == cEtherStakingMarket && msg.sender != address(0)), "Not allowed");
        address mediator = userCollateralMediator[user];
        if(mediator == address(0)){
            mediator = createCollateralStakingMediator(user);
        }
        return mediator;
    }

    /**
     * @notice create user's staking mediator contract proxy
     * @dev creates a new mediator contract and stores it in Staking Manager mapping
     * @param user of the user who stakes collateral
     */
    function createCollateralStakingMediator(address payable user) private returns(address) {
        CollateralStakingMediatorProxy mediatorContract = new CollateralStakingMediatorProxy(
            address(this),
            user,
            collateralStakingMediatorImplementation
        );
        address mediator = address(mediatorContract);
        emit NewCollateralStakingMediator(mediator);
        userCollateralMediator[user] = mediator;
        return mediator;
    }

    /**
     * @notice let user create a mediator contract to stake uncollateralized Erc20 outside of borrow/lend protocol
     * @dev this function can only be called once by address
     * @param amount the amount user wants to stake
     */
    function stakeInitialUncollateralizedErc20(uint256 amount) external {
        address mediator = userCollateralMediator[msg.sender];
        require(mediator == address(0), "Cannot send initial stake more than once - mediator already exists");
        require(amount > 0, "Initial stake must be larger than 0");
        mediator = createCollateralStakingMediator(msg.sender);
        SafeErc20.safeTransferFrom(restakingUnderlying, msg.sender, mediator, amount);
        CollateralStakingMediatorInterface(mediator).stakeUncollateralizedErc20(amount);
    }

    /**
     * @notice let user create a mediator contract to delegate uncollateralized Ron outside of borrow/lend protocol
     * @dev this function can only be called once by address
     * @param consensusAddr the pool where to delegate
     */
    function delegateInitialUncollateralizedRon(address consensusAddr) external payable {
        address mediator = userCollateralMediator[msg.sender];
        require(mediator == address(0), "Cannot send initial delegation more than once - mediator already exists");
        require(msg.value > 0, "Initial delegation must be larger than 0");
        mediator = createCollateralStakingMediator(msg.sender);
        CollateralStakingMediatorInterface(mediator).delegateUncollateralizedRon.value(msg.value)(consensusAddr);
    }
    
    /**
     * @notice support new CErcStaking market (either ERC20 or ERC721)
     * @param market of the CErcStaking market
     * @param stakingPool of the pool for the CErcStaking contract tokenKind
     * @param underlyingToken of the underlying token of this pool
     * @param isErc721 indicates if market is erc721
     * @param isErc20 indicates if market is erc20
     */
    function supportCErcStakingMarket(
        address market, 
        address stakingPool, 
        address underlyingToken, 
        bool isErc721, 
        bool isErc20
    ) external {
        require(msg.sender == admin, "Not allowed");
        if (isErc721) {
            require(
                CErc721StakingInterface(market).isCErc721Staking(), 
                "Not a valid market"
            );
        } else if (isErc20) {
            require(
                CErc20StakingInterface(market).isCErc20Staking(), 
                "Not a valid market"
            );
        }

        cErcStakingMarket[market] = true;
        marketPoolWire[market] = MarketPoolWire(stakingPool, underlyingToken);
        emit NewStakingMarket(market, stakingPool, underlyingToken);
    }

    /**
     * @notice support new CEtherStaking market (staked RON)
     * @param newCEtherStakingMarket address of the market
     */
    function supportCEtherStakingMarket(address newCEtherStakingMarket) external {
        require(msg.sender == admin, "Not allowed");
        require(newCEtherStakingMarket != address(0), "CEtherStaking market cannot be zero address");
        require(CEtherStakingInterface(newCEtherStakingMarket).isCEtherStaking(), "Not a valid market");
        emit NewCEtherStakingMarket(newCEtherStakingMarket, cEtherStakingMarket);
        cEtherStakingMarket = newCEtherStakingMarket;
    }

    /**
     * @notice set new percentage cut from collected rewards
     * @param newPercentage new percentage, scale 0 <=> 10000, 1% = 100
     */
    function setRewardRoyaltiesPercentage(uint256 newPercentage) external {
        require(msg.sender == admin, "Not allowed");
        require(newPercentage <= feeDenominator(), "Percentage overflow");
        emit NewRewardsRoyaltiesPercentage(newPercentage, rewardsRoyaltiesPercentage);
        rewardsRoyaltiesPercentage = newPercentage;
    }

    function feeDenominator() public pure returns (uint256) {
        return 10000;
    }

    /**
     * @notice set new admin
     * @param newAdmin new admin
     */
    function setAdmin(address newAdmin) external {
        require(msg.sender == admin, "Not allowed");
        require(newAdmin != address(0), "admin cannot be zero address");
        emit NewAdmin(newAdmin, admin);
        admin = newAdmin;
    }

    /**
     * @notice set new receiver of royalties
     * @param newReceiver new receiver
     */
    function setRoyaltiesReceiver(address payable newReceiver) external {
        require(msg.sender == admin, "Not allowed");
        require(newReceiver != address(0), "royalties receiver cannot be zero address");
        emit NewRoyaltiesReceiver(newReceiver, royaltiesReceiver);
        royaltiesReceiver = newReceiver;
    }

    /**
     * @notice set the restaking pool
     * @param restakingPool the pool where claimed rewards are restaked
     */
    function setRestakingPoolErc20(address restakingPool) external {
        require(msg.sender == admin, "Not allowed");
        require(restakingPool != address(0), "restaking pool cannot be zero address");
        emit NewRestakingPool(restakingPool, restakingPoolErc20);
        restakingPoolErc20 = restakingPool;
    }

    /**
     * @notice set the underlying token of restaking pool
     * @param underlying the underlying token of the pool where claimed rewards are restaked
     */
    function setRestakingUnderlying(address underlying) external {
        require(msg.sender == admin, "Not allowed");
        require(underlying != address(0), "underlying cannot be zero address");
        emit NewRestakingUnderlying(underlying, restakingUnderlying);
        restakingUnderlying = underlying;
    }
    
    /**
     * @notice set new implementation for all mediator proxies
     * @param newImplementation new implementation for proxies
     */
    function setCollateralStakingMediatorImplementation(address newImplementation) external {
        require(msg.sender == admin, "Not allowed");
        require(
            CollateralStakingMediatorInterface(newImplementation).isCollateralStakingMediator(), "Not a mediator implementation"
        );
        emit NewCollateralStakingMediatorImplementation(collateralStakingMediatorImplementation, newImplementation);
        collateralStakingMediatorImplementation = newImplementation;
    }

    function decreaseTotalRestakingAmount(uint256 amount) external {
        require(
            tx.origin == restakingManager || userCollateralMediator[tx.origin] == msg.sender,
            "Tx origin must be mediator or restaking manager"
        );
        totalRestakingAmount = totalRestakingAmount.sub(amount);
    }

    function increaseTotalRestakingAmount(uint256 amount) external {
        require(
            tx.origin == restakingManager || userCollateralMediator[tx.origin] == msg.sender,
            "Tx origin must be mediator or restaking manager"
        );
        totalRestakingAmount = totalRestakingAmount.add(amount);
    }

    function increaseTotalAccruedRewards(uint256 amount) external {
        require(
            tx.origin == restakingManager || userCollateralMediator[tx.origin] == msg.sender,
            "Tx origin must be mediator or restaking manager"
        );
        totalAccruedRewards = totalAccruedRewards.add(amount);
    }

    function setRestakingManager(address newManager) external {
        require(msg.sender == admin, "Not allowed");
        require(newManager != address(0), "restaking manager cannot be zero address");
        emit NewRestakingManager(newManager, restakingManager);
        restakingManager = newManager;
    }

    function setMoveUncollateralizedPaused(bool value) external {
        require(msg.sender == admin, "Not allowed");
        emit MoveCollateralPausedChanged(value);
        moveUncollateralizedPaused = value;
    }

    /**
     * @notice set new address for ronin staking contract
     * @param newRoninStaking the new ronin staking
     */
    function setRoninStaking(address newRoninStaking) external {
        require(msg.sender == admin, "Not allowed");
        require(newRoninStaking != address(0), "ronin staking cannot be zero address");
        emit NewRoninStaking(newRoninStaking, roninStaking);
        roninStaking = newRoninStaking;
    }

    /**
     * @notice set new address for ronin validator set
     * @param newRoninValidatorSet the new ronin validator set
     */
    function setRoninValidatorSet(address newRoninValidatorSet) external {
        require(msg.sender == admin, "Not allowed");
        require(newRoninValidatorSet != address(0), "ronin validator set cannot be zero address");
        emit NewRoninValidatorSet(newRoninValidatorSet, roninValidatorSet);
        roninValidatorSet = newRoninValidatorSet;
    }

    function setRedelegatingManager(address newRedelegatingManager) external {
        require(msg.sender == admin, "Not allowed");
        require(newRedelegatingManager != address(0), "redelegating manager cannot be zero address");
        emit NewRedelegatingManager(newRedelegatingManager, redelegatingManager);
        redelegatingManager = newRedelegatingManager;
    }

    function getSupportedValidatorsList() external view returns(address[] memory) {
        return supportedValidatorsList;
    }

    /**
     * @notice support a validator for RON and restaking
     * @dev one way process. Validator cannot be un-supported at this point because the length of supported validators cannot decrease
     *  due to targets for restaking (user must always have at least 1 validator non-collateralized)
     * @param validators the list of validators to support
     */
    function supportValidators(address[] calldata validators) external {
        require(msg.sender == admin, "Not allowed");
        for (uint256 i = 0; i < validators.length; i++) {
            supportedValidators[validators[i]] = true;
            bool addToArray = true;
            for (uint256 j = 0; j < supportedValidatorsList.length; j++) {
                if (supportedValidatorsList[j] == validators[i]) {
                    addToArray = false;
                    break;
                }
            }
            if (addToArray) {
                supportedValidatorsList.push(validators[i]);
            }
            emit ValidatorSupported(validators[i], true);
        }
    }

    function decreaseTotalDelegatingAmount(uint256 amount) external {
        require(
            tx.origin == redelegatingManager || userCollateralMediator[tx.origin] == msg.sender,
            "Tx origin must be mediator or redelegating manager"
        );
        totalDelegatingAmountRon = totalDelegatingAmountRon.sub(amount);
    }

    function increaseTotalDelegatingAmount(uint256 amount) external {
        require(
            tx.origin == redelegatingManager || userCollateralMediator[tx.origin] == msg.sender,
            "Tx origin must be mediator or redelegating manager"
        );
        totalDelegatingAmountRon = totalDelegatingAmountRon.add(amount);
    }
    
    function increaseTotalAccruedRewardsRon(uint256 amount) external {
        require(
            tx.origin == redelegatingManager || userCollateralMediator[tx.origin] == msg.sender,
            "Tx origin must be mediator or redelegating manager"
        );
        totalAccruedRewardsRon = totalAccruedRewardsRon.add(amount);
    }
}