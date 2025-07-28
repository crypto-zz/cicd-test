pragma solidity ^0.5.16;

import "./CollateralStakingMediatorInterface.sol";
import "../../Interface/ERC721Interface.sol";
import "../../Interface/RoninStakingInterfaces.sol";
import "../../Interface/EIP20Interface.sol";
import "../../Interface/EIP20NonStandardInterface.sol";
import "../../Interface/ERC721Interface.sol";
import "../../Lib/Math/ExponentialNoError.sol";
import "../../Lib/SafeErc20/SafeErc20.sol";

/**
 * @title MetaLend's CollateralStakingMediator Contract
 * @notice Manages staking of collateral to official onchain staking contracts to accrue rewards
 * @author MetaLend
 */
contract CollateralStakingMediator is CollateralStakingMediatorInterface, IERC721Receiver, ExponentialNoError {
    /**
     * @notice Initialize the mediator contract
     * @param collateralStakingManager_ The CollateralStakingManager contract which is shared among all mediator contracts
     * @param owner_ The owner of the mediator contract (user with collateral in protocol)
     */
    function initialize(
        address collateralStakingManager_,
        address payable owner_
    ) external {
        require(!initialized, "Can only be initialized once");
        require(owner_ != address(0), "owner cannot be zero address");

        collateralStakingManager = CollateralStakingManagerInterface(collateralStakingManager_);
        
        owner = owner_;
        initialized = true;
    }

    modifier nonReentrant() {
        require(!_entered, "re-entered");
        _entered = true;
        _;
        _entered = false;
    }

    /**
     * @notice Stake `tokenIds` to ERC721 staking contract to accrue rewards
     * @dev Called only by CErc721Staking contract during mint function
     * token ids first MUST be transferred from CErc721Staking contract to this contract
     * @param tokenIds The token ids to stake
     */
    function stakeErc721(uint256[] calldata tokenIds) external {
        require(collateralStakingManager.cErcStakingMarket(msg.sender), "Not allowed");
        (address stakingPool, address underlying) = collateralStakingManager.marketPoolWire(msg.sender);
        require(!Erc721StakingPool(stakingPool).paused(), "Staking is paused");
        ERC721Interface(underlying).setApprovalForAll(stakingPool, true);
        Erc721StakingPool(stakingPool).stake(tokenIds);
    }

    /**
     * @notice Stake `amount` to ERC20 staking contract to accrue rewards
     * @dev Called only by CErc20Staking contract during mint function
     * amount first MUST be transferred from CErc20Staking contract to this contract
     * this MUST not modify uncollateralizedStakingAmount
     * @param amount The amount to stake
     */
    function stakeErc20(uint256 amount) external {
        require(collateralStakingManager.cErcStakingMarket(msg.sender), "Not allowed");
        (address stakingPool, address underlying) = collateralStakingManager.marketPoolWire(msg.sender);
        //require(!Erc20StakingPool(stakingPool).paused(0xa694fc3a), "Staking is paused"); // 0xa694fc3a is stake method
        EIP20Interface(underlying).approve(stakingPool, amount);
        Erc20StakingPool(stakingPool).stake(amount);
    }

    /**
     * @notice Unstake `tokenIds` from ERC721 staking contract
     * @dev Called only by CErc721Staking contract during redeem/seizeAndRedeem functions
     * token ids are transferred from this contract to receiver
     * @param tokenIds The token ids to unstake
     * @param receiver Where to send tokens - redeemer / liquidator
     */
    function unstakeErc721(uint256[] calldata tokenIds, address receiver) external {
        require(collateralStakingManager.cErcStakingMarket(msg.sender), "Not allowed");
        (address stakingPool, address underlying) = collateralStakingManager.marketPoolWire(msg.sender);
        Erc721StakingPool(stakingPool).unstake(tokenIds);
        ERC721Interface tokenContract = ERC721Interface(underlying);
        for(uint i = 0; i < tokenIds.length; i++) {
            tokenContract.safeTransferFrom(address(this), receiver, tokenIds[i]);
        }
    }

    /**
     * @notice Unstake `amount` from ERC20 staking contract
     * @dev Called only by CErc20Staking contract during redeem/seizeAndRedeem functions
     * amount is transferred from this contract to receiver
     * @param amount The amount to unstake
     * @param receiver Where to send tokens - redeemer / liquidator
     */
    function unstakeErc20(uint256 amount, address receiver) external {
        require(collateralStakingManager.cErcStakingMarket(msg.sender), "Not allowed");
        (address stakingPool, address underlying) = collateralStakingManager.marketPoolWire(msg.sender);
        Erc20StakingPool(stakingPool).unstake(amount);
        SafeErc20.safeTransfer(underlying, receiver, amount);
    }

    /**
     * @notice Claim rewards from pool
     * @dev Called only by owner of this mediator contract (person who stakes collateral to protocol)
     * @param stakingPool staking pool where rewards are available
     * @param stakingManager staking manager for the staking pool
     */
    function claimPendingRewards(address stakingPool, address stakingManager) external {
        require(msg.sender == owner, "Not allowed");
        
        StakingPool pool = StakingPool(stakingPool);
        require(StakingManager(stakingManager).canObtainRewards(stakingPool, address(this)), "Cannot claim");

        pool.claimPendingRewards();
        address underlyingContract = pool.getRewardToken();

        uint256 royaltiesPercentage = collateralStakingManager.rewardsRoyaltiesPercentage();

        if(royaltiesPercentage != 0){
            address royaltiesReceiver = collateralStakingManager.royaltiesReceiver();
            
            uint balanceCurrent = EIP20Interface(underlyingContract).balanceOf(address(this));
            
            uint royaltiesAmount = div_(mul_(balanceCurrent, royaltiesPercentage), collateralStakingManager.feeDenominator());
            SafeErc20.safeTransfer(underlyingContract, royaltiesReceiver, royaltiesAmount);
        }
        
        uint remainingAmount = EIP20Interface(underlyingContract).balanceOf(address(this));
        SafeErc20.safeTransfer(underlyingContract, owner, remainingAmount);
        accruedRewards[stakingPool] = add_(accruedRewards[stakingPool], remainingAmount);
    }

    /**
     * @notice stake assets outside of borrow/lend protocol
     * @dev this can only be called by mediator owner or by CollateralStakingManager
     * @param amount the user wants to stake
     */
    function stakeUncollateralizedErc20(uint256 amount) external {
        require(msg.sender == owner || msg.sender == address(collateralStakingManager), "Not allowed");
        address restakingPool = collateralStakingManager.restakingPoolErc20();
        address restakingUnderlying = collateralStakingManager.restakingUnderlying();
        // if owner sends this transaction, transfer from owner's wallet
        // otherwise amount is transferred by manager to this contract
        if (msg.sender == owner) {
            SafeErc20.safeTransferFrom(restakingUnderlying, owner, address(this), amount);
        }
        EIP20Interface(restakingUnderlying).approve(restakingPool, amount);
        Erc20StakingPool(restakingPool).stake(amount);
        uncollateralizedStakingAmount = add_(uncollateralizedStakingAmount, amount);
        collateralStakingManager.increaseTotalRestakingAmount(amount);
    }

    /**
     * @notice Unstakes the uncollateralized assets
     * @dev no liquidity sanity checks required as this does not contribute towards collateral balance
     * @param amount the amount to unstake which must be less than or equal to uncollateralizedStakingAmount
     */
    function unstakeUncollateralizedErc20(uint256 amount) external {
        require(msg.sender == owner, "Not allowed");
        require(amount <= uncollateralizedStakingAmount, "Not enough uncollateralized tokens to unstake");
        address restakingPool = collateralStakingManager.restakingPoolErc20();
        address restakingUnderlying = collateralStakingManager.restakingUnderlying();
        Erc20StakingPool(restakingPool).unstake(amount);
        SafeErc20.safeTransfer(restakingUnderlying, owner, amount);
        uncollateralizedStakingAmount = sub_(uncollateralizedStakingAmount, amount);
        collateralStakingManager.decreaseTotalRestakingAmount(amount);
    }

    /**
     * @notice Restake rewards from pool
     * @param stakingPool staking pool where rewards are available
     * @param stakingManager staking manager for the staking pool
     */
    function restakePendingRewards(address stakingPool, address stakingManager) external {
        require(msg.sender == collateralStakingManager.restakingManager(), "Only restaking manager can do this operation");
        StakingPool pool = StakingPool(stakingPool);
        require(StakingManager(stakingManager).canObtainRewards(stakingPool, address(this)), "Cannot claim");

        pool.claimPendingRewards();
        address underlyingContract = pool.getRewardToken();

        uint256 royaltiesPercentage = collateralStakingManager.rewardsRoyaltiesPercentage();
        address restakingPool = collateralStakingManager.restakingPoolErc20();

        if(royaltiesPercentage != 0){
            address royaltiesReceiver = collateralStakingManager.royaltiesReceiver();
            
            uint balanceCurrent = EIP20Interface(underlyingContract).balanceOf(address(this));
            
            uint royaltiesAmount = div_(mul_(balanceCurrent, royaltiesPercentage), collateralStakingManager.feeDenominator());
            SafeErc20.safeTransfer(underlyingContract, royaltiesReceiver, royaltiesAmount);
        }
        
        uint remainingAmount = EIP20Interface(underlyingContract).balanceOf(address(this));
        EIP20NonStandardInterface(underlyingContract).approve(restakingPool, remainingAmount);
        Erc20StakingPool(restakingPool).stake(remainingAmount);
        uncollateralizedStakingAmount = add_(uncollateralizedStakingAmount, remainingAmount);
        collateralStakingManager.increaseTotalRestakingAmount(remainingAmount);
        collateralStakingManager.increaseTotalAccruedRewards(remainingAmount);
        accruedRewards[stakingPool] = add_(accruedRewards[stakingPool], remainingAmount);
    }

    /**
     * @notice Move funds to borrow/lend pool
     * @dev This function MUST only be called by CErc20Staking collateral contract and the underlying token and pool 
     *  of this supported market MUST equal to `restakingPool` and `restakingUnderlying`
     *  `msg.sender` MUST be CErc20Staking contract which is supported in CollateralStakingManager
     * @param amount the uncollateralized amount to move from non-borrowable staking amount to protocol collateral
     */
    function moveUncollateralizedErc20ToProtocol(uint256 amount) external {
        require(!collateralStakingManager.moveUncollateralizedPaused(), "Moving funds paused");
        require(collateralStakingManager.cErcStakingMarket(msg.sender), "Not allowed");
        (address stakingPool, address underlying) = collateralStakingManager.marketPoolWire(msg.sender);
        address restakingPool = collateralStakingManager.restakingPoolErc20();
        address restakingUnderlying = collateralStakingManager.restakingUnderlying();

        require(stakingPool == restakingPool, "Incorrect pool");
        require(underlying == restakingUnderlying, "Incorrect underlying token");
        require(amount <= uncollateralizedStakingAmount, "Not enough uncollateralized tokens to move");
        uncollateralizedStakingAmount = sub_(uncollateralizedStakingAmount, amount);
        collateralStakingManager.decreaseTotalRestakingAmount(amount);
    }

    /**
     * @notice Claim rewards from delegation
     * @dev Called only by owner of this mediator contract (person who delegates via this mediator)
     * @param consensusAddrList the list of delegating validators to claim rewards from
     */
    function claimRewardsRon(address[] calldata consensusAddrList) external nonReentrant {
        require(msg.sender == owner, "Not allowed");

        RoninStaking(collateralStakingManager.roninStaking()).claimRewards(consensusAddrList);

        if (address(this).balance == 0) {
            return;
        }

        uint256 royaltiesPercentage = collateralStakingManager.rewardsRoyaltiesPercentage();
        if(royaltiesPercentage != 0){
            address payable royaltiesReceiver = collateralStakingManager.royaltiesReceiver();
            
            uint royaltiesAmount = div_(mul_(address(this).balance, royaltiesPercentage), collateralStakingManager.feeDenominator());
            royaltiesReceiver.transfer(royaltiesAmount);
        }
        
        uint remainingAmount = address(this).balance;
        owner.transfer(remainingAmount);
        accruedRewardsRon = add_(accruedRewardsRon, remainingAmount);
    }

    /**
     * @notice Undelegates the uncollateralized assets
     * @dev no liquidity sanity checks required as this does not contribute towards collateral balance
     *  `consensusAddrList` length must be equal to `amounts` length
     * @param consensusAddrList the list of pools from which to undelegate, cannot contain a validator used for collateral
     * @param amounts the amounts to undelegate from each validator
     */
    function undelegateUncollateralizedRon(address[] calldata consensusAddrList, uint256[] calldata amounts) external nonReentrant {
        require(msg.sender == owner, "Not allowed");
        require(consensusAddrList.length == amounts.length, "Incorrect input lengths");
        uint256 amountsSum;
        for (uint256 i = 0; i < amounts.length; i++) {
            address validator = consensusAddrList[i];
            require(!validatorUsedForCollateral[validator], "Validator used for collateralized RON");
            amountsSum = add_(amounts[i], amountsSum);
            if (amounts[i] == RoninStaking(collateralStakingManager.roninStaking()).getStakingAmount(validator, address(this))) {
                validatorToRestakingTarget[validator] = address(0);
            }
        }        
        RoninStaking(collateralStakingManager.roninStaking()).bulkUndelegate(consensusAddrList, amounts);
        owner.transfer(amountsSum);
        collateralStakingManager.decreaseTotalDelegatingAmount(amountsSum);
    }

    /**
     * @notice delegate assets outside of borrow/lend protocol
     * @dev this can only be called by mediator owner or by CollateralStakingManager (during creation of mediator)
     *  Pass msg.value as the amount to delegate
     * @param consensusAddr the pool for delegation
     */
    function delegateUncollateralizedRon(address consensusAddr) external payable {
        require(msg.sender == owner || msg.sender == address(collateralStakingManager), "Not allowed");
        require(collateralStakingManager.supportedValidators(consensusAddr), "Not a supported validator");
        require(!validatorUsedForCollateral[consensusAddr], "Validator used for collateralized RON");
        RoninStaking(collateralStakingManager.roninStaking()).delegate.value(msg.value)(consensusAddr);
        poolToUndelegateCooldown[consensusAddr] = add_(
            block.timestamp, 
            RoninStaking(collateralStakingManager.roninStaking()).cooldownSecsToUndelegate()
        );        
        collateralStakingManager.increaseTotalDelegatingAmount(msg.value);
    }

    /**
     * @notice delegate assets as collateral for the protocol
     * @dev this can only be called by CEtherStaking contract (collateralized RON)
     *  Pass msg.value as the amount to delegate
     * @param consensusAddr the pool for delegation
     * @param consensusAddrTarget target for restaking rewards of the collateralized validator
     */
    function delegateCollateralizedRon(address consensusAddr, address consensusAddrTarget) external payable {
        require(collateralStakingManager.cEtherStakingMarket() == msg.sender && msg.sender != address(0), "Not allowed");
        require(collateralStakingManager.supportedValidators(consensusAddr), "Not a supported validator");
        require(collateralStakingManager.supportedValidators(consensusAddrTarget), "Target is not a supported validator");
        require(!validatorUsedForCollateral[consensusAddr], "Validator used for collateralized RON");
        require(!validatorUsedForCollateral[consensusAddrTarget], "Target used for collateralized RON");
        uint256 uncollateralizedAmount = RoninStaking(collateralStakingManager.roninStaking()).getStakingAmount(consensusAddr, address(this));
        RoninStaking(collateralStakingManager.roninStaking()).delegate.value(msg.value)(consensusAddr);
        poolToUndelegateCooldown[consensusAddr] = add_(
            block.timestamp, 
            RoninStaking(collateralStakingManager.roninStaking()).cooldownSecsToUndelegate()
        );
        activeCollateralizedValidators.push(consensusAddr);
        validatorUsedForCollateral[consensusAddr] = true;
        validatorToRestakingTarget[consensusAddr] = consensusAddrTarget;
        address[] memory allSupportedValidators = collateralStakingManager.getSupportedValidatorsList();
        for (uint256 i = 0; i < allSupportedValidators.length; i++) {
            if (validatorToRestakingTarget[allSupportedValidators[i]] == consensusAddr) {
                validatorToRestakingTarget[allSupportedValidators[i]] = consensusAddrTarget;
            }
        }

        if (uncollateralizedAmount > 0) {
            collateralStakingManager.decreaseTotalDelegatingAmount(uncollateralizedAmount);
        }
    }

    /**
     * @notice Restake rewards from delegation
     * @param consensusAddrList the addresses of pools from which to claim rewards
     */
    function redelegateRewards(address[] calldata consensusAddrList) external {
        require(msg.sender == collateralStakingManager.redelegatingManager(), "Only restaking manager can do this operation");

        RoninStaking staking = RoninStaking(collateralStakingManager.roninStaking());
        uint256[] memory claimableRewards = staking.getRewards(address(this), consensusAddrList);

        staking.claimRewards(consensusAddrList);
        uint256 fullBalance = address(this).balance;
        if (fullBalance == 0) {
            return;
        }

        uint256 royaltiesPercentage = collateralStakingManager.rewardsRoyaltiesPercentage();
        if(royaltiesPercentage != 0){
            address payable royaltiesReceiver = collateralStakingManager.royaltiesReceiver();
            
            uint royaltiesAmount = div_(mul_(fullBalance, royaltiesPercentage), collateralStakingManager.feeDenominator());
            royaltiesReceiver.transfer(royaltiesAmount);
        }

        uint256 lastValidatorWithRewards;
        for (uint256 i = consensusAddrList.length - 1; i >= 0; i--) {
            if (i == 0) {
                break;
            }
            if (claimableRewards[i] > 0) {
                lastValidatorWithRewards = i;
                break;
            }
        }
        
        uint remainingAmount = address(this).balance;
        uint cooldown = RoninStaking(collateralStakingManager.roninStaking()).cooldownSecsToUndelegate();
        for (uint256 i = 0; i < consensusAddrList.length; i++) {
            if (claimableRewards[i] == 0) {
                continue;
            }
            uint toDelegate;

            if (i == lastValidatorWithRewards) {
                toDelegate = address(this).balance;
            } else {
                uint256 percentage = div_(mul_(claimableRewards[i], 1000000000000000000), fullBalance);
                toDelegate = div_(mul_(remainingAmount, percentage), 1000000000000000000);
            }

            address target = validatorToRestakingTarget[consensusAddrList[i]];
            if (target == address(0)) {
                target = consensusAddrList[i];
            }
            require(!validatorUsedForCollateral[target], "Validator used for collateralized RON");
            staking.delegate.value(toDelegate)(target);
            poolToUndelegateCooldown[target] = add_(
                block.timestamp, 
                cooldown
            );
        }
        
        collateralStakingManager.increaseTotalDelegatingAmount(remainingAmount);
        collateralStakingManager.increaseTotalAccruedRewardsRon(remainingAmount);
        accruedRewardsRon = add_(accruedRewardsRon, remainingAmount);
    }

    /**
     * @notice adds validator stake to collateral for the protocol
     * @dev this does not move funds around, it only rewrites state
     * @param consensusAddr address of the validator
     * @param consensusAddrTarget target for restaking rewards of the collateralized validator
     */
    function moveUncollateralizedRonToProtocol(address consensusAddr, address consensusAddrTarget) external {
        require(collateralStakingManager.cEtherStakingMarket() == msg.sender && msg.sender != address(0), "Not allowed");
        require(!validatorUsedForCollateral[consensusAddr], "Validator used for collateralized RON");
        uint256 amount = RoninStaking(collateralStakingManager.roninStaking()).getStakingAmount(consensusAddr, address(this));
        require(amount > 0, "Staking amount must be greater than 0");
        require(!validatorUsedForCollateral[consensusAddrTarget], "Target used for collateralized RON");
        require(collateralStakingManager.supportedValidators(consensusAddrTarget), "Not a supported validator");
        collateralStakingManager.decreaseTotalDelegatingAmount(amount);
        activeCollateralizedValidators.push(consensusAddr);
        validatorUsedForCollateral[consensusAddr] = true;
        validatorToRestakingTarget[consensusAddr] = consensusAddrTarget;
        address[] memory allSupportedValidators = collateralStakingManager.getSupportedValidatorsList();
        for (uint256 i = 0; i < allSupportedValidators.length; i++) {
            if (validatorToRestakingTarget[allSupportedValidators[i]] == consensusAddr) {
                validatorToRestakingTarget[allSupportedValidators[i]] = consensusAddrTarget;
            }
        }
    }

    /**
     * @notice redeems tokens from collateralized validators
     * @dev this function is used for both owner withdrawal and liquidations
     * @param consensusAddrList list of validators to withdraw from
     * @param redeemTokens amount per validator sorted
     * @param to address to send the RON to
     */
    function redeemCollateralizedRon(address[] calldata consensusAddrList, uint[] calldata redeemTokens, address payable to) external nonReentrant {
        require(collateralStakingManager.cEtherStakingMarket() == msg.sender && msg.sender != address(0), "Not allowed");
        require(consensusAddrList.length == redeemTokens.length, "Incorrect input size");

        uint256 amountsSum;
        for (uint256 i = 0; i < consensusAddrList.length; i++) {
            address consensusAddr = consensusAddrList[i];
            if (consensusAddr == address(0)) {
                continue;
            }
            uint256 withdrawAmount = redeemTokens[i];
            amountsSum = add_(amountsSum, withdrawAmount);
            require(validatorUsedForCollateral[consensusAddr], "Validator not used for collateralized RON");
            uint256 stakingAmount = RoninStaking(collateralStakingManager.roninStaking()).getStakingAmount(consensusAddr, address(this));
            
            // all RON has been withdrawn from validator, reset
            if (sub_(stakingAmount, withdrawAmount) == 0) {
                address[] storage userActiveValidators = activeCollateralizedValidators;
                uint256 activeValidatorIndex;
                for (uint256 j = 0; j < userActiveValidators.length; j++) {
                    if (userActiveValidators[j] == consensusAddr) {
                        activeValidatorIndex = j;
                        break;
                    }
                }
                // copy last item in-place of current consensusAddr and remove the last item
                userActiveValidators[activeValidatorIndex] = userActiveValidators[userActiveValidators.length - 1];
                userActiveValidators.length--;
                validatorUsedForCollateral[consensusAddr] = false;
                validatorToRestakingTarget[consensusAddr] = address(0);
            }
            RoninStaking(collateralStakingManager.roninStaking()).undelegate(consensusAddr, withdrawAmount);    
        }
        to.transfer(amountsSum);
    }

    function setValidatorTargetsForRestaking(address consensusAddrSrc, address consensusAddrDst) external {
        require(msg.sender == owner, "Not allowed");
        require(collateralStakingManager.supportedValidators(consensusAddrSrc), "Not a supported validator");
        require(collateralStakingManager.supportedValidators(consensusAddrDst), "Target is not a supported validator");
        require(!validatorUsedForCollateral[consensusAddrDst], "Target used for collateralized RON");
        validatorToRestakingTarget[consensusAddrSrc] = consensusAddrDst;

        if (!validatorUsedForCollateral[consensusAddrSrc]) {
            address[] memory allSupportedValidators = collateralStakingManager.getSupportedValidatorsList();
            for (uint256 i = 0; i < allSupportedValidators.length; i++) {
                if (validatorToRestakingTarget[allSupportedValidators[i]] == consensusAddrSrc) {
                    validatorToRestakingTarget[allSupportedValidators[i]] = consensusAddrDst;
                }
            }
        }
    }

    function getActiveCollateralizedValidators() external view returns(address[] memory) {
        return activeCollateralizedValidators;
    }
    
    /**
     * @notice Get pending rewards from selected pool
     * @param stakingPool staking pool where rewards are available
     * @return uint the amount the owner of this contract can claim
     */
    function getPendingRewards(address stakingPool) external view returns(uint256) {
        return StakingPool(stakingPool).getPendingRewards(address(this));
    }

    /**
     * @notice Get if rewards can be claimed from selected pool
     * @param stakingManager staking pool where rewards are available
     * @param stakingPool staking manager for the staking pool
     * @return bool true if rewards can be called
     */
    function canClaimRewards(address stakingManager, address stakingPool) external view returns(bool) {
        return StakingManager(stakingManager).canObtainRewards(stakingPool, address(this));
    }

    /**
     * @notice get the mediator contract owner
     */
    function getOwner() external view returns(address) {
        return owner;
    }

    /**
      * @notice onERC721Received implementation to support safeTransferFrom
      */
    function onERC721Received(
        address, 
        address, 
        uint256, 
        bytes calldata
    ) external returns(bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    function() external payable {}
}
