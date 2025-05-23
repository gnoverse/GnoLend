package gnolend

import (
	"std"
	"time"

	"gno.land/p/demo/avl"
	"gno.land/p/demo/ownable"

	u256 "gno.land/p/gnoswap/uint256"
	pl "gno.land/r/gnoswap/v1/pool"
)

/* STATE VARIABLES */

var (
	markets *avl.Tree // marketId -> Market
	// First level: marketId -> *avl.Tree
	// Second level: userAddr -> Position
	positions    *avl.Tree
	marketParams *avl.Tree // marketId -> MarketParams
	enabledIRMs  *avl.Tree // irm -> bool
	enabledLLTVs *avl.Tree // lltv -> bool
	Ownable      *ownable.Ownable
	feeRecipient std.Address
	irmRegistry  *avl.Tree // irmName -> IRM
)

/* INITIALIZATION */

func init() {
	// Initialize market state
	markets = avl.NewTree()
	marketParams = avl.NewTree()
	positions = avl.NewTree()

	// Initialize enabled IRMs and LLTVs
	enabledIRMs = avl.NewTree()
	enabledLLTVs = avl.NewTree()

	// Initialize IRM registry
	irmRegistry = avl.NewTree()

	// Set initial owner
	Ownable = ownable.New()
}

/* ADMIN FUNCTIONS */

// RegisterIRM registers a new interest rate model
func RegisterIRM(irm IRM) {
	// Get IRM name
	name := irm.Name()

	// Check if IRM is already registered
	if _, exists := irmRegistry.Get(name); exists {
		panic("IRM already registered")
	}

	// Register the IRM
	irmRegistry.Set(name, irm)

	// Emit registration event
	emitRegisterIRM(std.PreviousRealm().PkgPath(), name)
}

func EnableIRM(irm string) {
	Ownable.AssertCallerIsOwner()

	// Check if IRM exists in registry
	if _, exists := irmRegistry.Get(irm); !exists {
		panic("IRM not registered: " + irm)
	}

	if _, exists := enabledIRMs.Get(irm); exists {
		panic(ErrAlreadySet)
	}

	enabledIRMs.Set(irm, true)
}

func EnableLLTV(lltv *u256.Uint) {
	Ownable.AssertCallerIsOwner()

	// Convert LLTV to string for use as key in tree
	lltvStr := lltv.ToString()

	if _, exists := enabledLLTVs.Get(lltvStr); exists {
		panic(ErrAlreadySet)
	}

	// Check if LLTV is greater than 100%
	maxLLTV := u256.NewUint(100)
	if lltv.Gt(maxLLTV) {
		panic(ErrMaxFeeExceeded) // Reuse fee error since both are percentages
	}

	enabledLLTVs.Set(lltvStr, true)
}

func SetFeeRecipient(newFeeRecipient std.Address) {
	Ownable.AssertCallerIsOwner()

	if newFeeRecipient == feeRecipient {
		panic(ErrAlreadySet)
	}

	feeRecipient = newFeeRecipient
}

/* MARKET CREATION */

// CreateMarket initializes a new lending market with basic parameters
func CreateMarket(poolPath string, isToken0Loan bool, irm string, lltv int64) {
	if poolPath == "" {
		panic(ErrZeroAddress)
	}

	// Verify pool exists in Gnoswap
	if !pl.DoesPoolPathExist(poolPath) {
		panic(ErrTokenPairNotInGnoswap)
	}

	// Convert LLTV percentage to WAD-scaled value (e.g., 75% -> 0.75 * 1e18)
	lltvUint := u256.NewUint(uint64(lltv))
	lltvWad := MulDivDown(lltvUint, WAD, u256.NewUint(100)) // This will give us (lltv * 1e18) / 100

	println("lltvWad:", lltvWad.ToString())

	// Create market params
	params := MarketParams{
		PoolPath:     poolPath,
		IRM:          irm,
		LLTV:         lltvWad,
		IsToken0Loan: isToken0Loan,
	}

	// Get market ID (same as pool path)
	marketId := params.ID()

	// Check market doesn't exist
	if _, exists := markets.Get(marketId); exists {
		panic(ErrMarketAlreadyCreated)
	}

	// Create market with initial values
	market := Market{
		TotalSupplyAssets: new(u256.Uint),
		TotalSupplyShares: new(u256.Uint),
		TotalBorrowAssets: new(u256.Uint),
		TotalBorrowShares: new(u256.Uint),
		LastUpdate:        time.Now().Unix(),
		Fee:               new(u256.Uint), // Initialize fee as zero
	}

	// Store market and its params
	markets.Set(marketId, market)
	marketParams.Set(marketId, params)

	// Initialize positions tree for this market
	positions.Set(marketId, avl.NewTree())

	// Get IRM from registry and verify it exists
	irmInstance := GetIRM(irm)
	if irmInstance == nil {
		panic("IRM not found: " + irm)
	}

	emitCreateMarket(marketId, params.GetLoanToken(), params.GetCollateralToken())
}

/* SUPPLY MANAGEMENT */

// Supply tokens to a market
// Either assets or shares must be non-zero (XOR)
func Supply(marketId string, assets, shares uint64) {
	if (assets > 0 && shares > 0) || (assets == 0 && shares == 0) {
		panic(ErrInconsistentAmount)
	}

	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	// Convert inputs to uint256
	assetsU256 := u256.NewUint(assets)
	sharesU256 := u256.NewUint(shares)

	caller := std.PreviousRealm().Address()

	// Get market and params
	market, params := GetMarket(marketId)

	// Accrue interest before any state changes
	accrueInterest(marketId)

	// Calculate shares to mint
	var sharesToMint *u256.Uint
	if assets > 0 {
		sharesToMint = ToSharesDown(
			assetsU256,
			market.TotalSupplyAssets,
			market.TotalSupplyShares,
		)
	} else {
		sharesToMint = sharesU256
		assetsU256 = ToAssetsUp(
			sharesU256,
			market.TotalSupplyAssets,
			market.TotalSupplyShares,
		)
	}

	// Get user's current position
	position := GetPosition(marketId, caller.String())

	// Update position
	position.SupplyShares = new(u256.Uint).Add(position.SupplyShares, sharesToMint)

	// Get market's positions tree and update position
	marketPositionsInterface, exists := positions.Get(marketId)
	if !exists {
		panic(ErrMarketNotCreated)
	}
	marketPositions := marketPositionsInterface.(*avl.Tree)
	marketPositions.Set(caller.String(), position)

	// Update market state
	market.TotalSupplyShares = new(u256.Uint).Add(market.TotalSupplyShares, sharesToMint)
	market.TotalSupplyAssets = new(u256.Uint).Add(market.TotalSupplyAssets, assetsU256)
	markets.Set(marketId, market)

	// Handle token transfer using GRC20 interface
	tokenTeller := GetTokenCallerTeller(params.GetLoanToken())
	if err := tokenTeller.TransferFrom(caller, std.CurrentRealm().Address(), assetsU256.Uint64()); err != nil {
		panic(err)
	}

	emitDeposit(marketId, caller, assetsU256)
}

// Withdraw tokens from a market
// Either assets or shares must be non-zero (XOR)
func Withdraw(marketId string, assets, shares uint64) {
	if (assets > 0 && shares > 0) || (assets == 0 && shares == 0) {
		panic(ErrInconsistentAmount)
	}

	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	// Convert inputs to uint256
	assetsU256 := u256.NewUint(assets)
	sharesU256 := u256.NewUint(shares)

	caller := std.PreviousRealm().Address()

	// Get market and params
	market, params := GetMarket(marketId)

	// Accrue interest before any state changes
	accrueInterest(marketId)

	// Calculate shares to burn
	var sharesToBurn *u256.Uint
	if assets > 0 {
		sharesToBurn = ToSharesUp(
			assetsU256,
			market.TotalSupplyAssets,
			market.TotalSupplyShares,
		)
	} else {
		sharesToBurn = sharesU256
		assetsU256 = ToAssetsDown(
			sharesU256,
			market.TotalSupplyAssets,
			market.TotalSupplyShares,
		)
	}

	// Get user's current position
	position := GetPosition(marketId, caller.String())

	// Check if user has enough shares
	if sharesToBurn.Gt(position.SupplyShares) {
		panic(ErrInsufficientShares)
	}

	// Update position
	position.SupplyShares = new(u256.Uint).Sub(position.SupplyShares, sharesToBurn)

	// Get market's positions tree and update position
	marketPositionsInterface, exists := positions.Get(marketId)
	if !exists {
		panic(ErrMarketNotCreated)
	}
	marketPositions := marketPositionsInterface.(*avl.Tree)
	marketPositions.Set(caller.String(), position)

	// Update market state
	market.TotalSupplyShares = new(u256.Uint).Sub(market.TotalSupplyShares, sharesToBurn)
	market.TotalSupplyAssets = new(u256.Uint).Sub(market.TotalSupplyAssets, assetsU256)
	markets.Set(marketId, market)

	// Check if there's enough liquidity after withdrawal
	if market.TotalBorrowAssets.Gt(market.TotalSupplyAssets) {
		panic(ErrInsufficientLiquidity)
	}

	// Handle token transfer using GRC20 interface
	tokenTeller := GetTokenCallerTeller(params.GetLoanToken())
	if err := tokenTeller.Transfer(caller, assetsU256.Uint64()); err != nil {
		panic(err)
	}

	emitWithdraw(marketId, caller, assetsU256)
}

/* BORROW MANAGEMENT */

// Borrow assets from a market using collateral
// Either assets or shares must be non-zero (not both)
func Borrow(marketId string, assets, shares uint64) {
	if (assets > 0 && shares > 0) || (assets == 0 && shares == 0) {
		panic(ErrInconsistentAmount)
	}

	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	// Convert inputs to uint256
	assetsU256 := u256.NewUint(assets)
	sharesU256 := u256.NewUint(shares)

	caller := std.PreviousRealm().Address()

	// Get market and params
	market, params := GetMarket(marketId)

	// Accrue interest before any state changes
	accrueInterest(marketId)

	// Get user's current position
	position := GetPosition(marketId, caller.String())

	// Check if user has collateral
	if position.Collateral.IsZero() {
		panic(ErrNoCollateral)
	}

	// Calculate shares to mint
	var sharesToMint *u256.Uint
	if assets > 0 {
		sharesToMint = ToSharesUp(
			assetsU256,
			market.TotalBorrowAssets,
			market.TotalBorrowShares,
		)
	} else {
		sharesToMint = sharesU256
		assetsU256 = ToAssetsDown(
			sharesU256,
			market.TotalBorrowAssets,
			market.TotalBorrowShares,
		)
	}

	// Check if market has sufficient liquidity
	availableLiquidity := new(u256.Uint).Sub(market.TotalSupplyAssets, market.TotalBorrowAssets)
	if assetsU256.Cmp(availableLiquidity) > 0 {
		panic(ErrInsufficientLiquidity)
	}

	// Update position
	position.BorrowShares = new(u256.Uint).Add(position.BorrowShares, sharesToMint)

	// Get market's positions tree and update position temporarily to check health
	marketPositionsInterface, exists := positions.Get(marketId)
	if !exists {
		panic(ErrMarketNotCreated)
	}
	marketPositions := marketPositionsInterface.(*avl.Tree)
	marketPositions.Set(caller.String(), position)

	// Check if position would be healthy after borrow
	if !isHealthy(marketId, caller.String()) {
		panic(ErrExceedsLTV)
	}

	// Update market state
	market.TotalBorrowShares = new(u256.Uint).Add(market.TotalBorrowShares, sharesToMint)
	market.TotalBorrowAssets = new(u256.Uint).Add(market.TotalBorrowAssets, assetsU256)
	markets.Set(marketId, market)

	// Transfer borrowed tokens to caller
	tokenTeller := GetTokenCallerTeller(params.GetLoanToken())
	if err := tokenTeller.Transfer(caller, assetsU256.Uint64()); err != nil {
		panic(err)
	}

	emitBorrow(marketId, caller, assetsU256)
}

// Repay borrowed tokens to a market
// Either assets or shares must be non-zero (XOR)
func Repay(marketId string, assets, shares uint64) {
	if (assets > 0 && shares > 0) || (assets == 0 && shares == 0) {
		panic(ErrInconsistentAmount)
	}

	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	// Convert inputs to uint256
	assetsU256 := u256.NewUint(assets)
	sharesU256 := u256.NewUint(shares)

	caller := std.PreviousRealm().Address()

	// Get market and params
	market, params := GetMarket(marketId)

	// Accrue interest before any state changes
	accrueInterest(marketId)

	// Calculate shares to burn
	var sharesToBurn *u256.Uint
	if assets > 0 {
		sharesToBurn = ToSharesDown(
			assetsU256,
			market.TotalBorrowAssets,
			market.TotalBorrowShares,
		)
	} else {
		sharesToBurn = sharesU256
		assetsU256 = ToAssetsUp(
			sharesU256,
			market.TotalBorrowAssets,
			market.TotalBorrowShares,
		)
	}

	// Get user's current position
	position := GetPosition(marketId, caller.String())

	// Check if user has enough shares
	if sharesToBurn.Gt(position.BorrowShares) {
		panic(ErrInsufficientShares)
	}

	// Update position
	position.BorrowShares = new(u256.Uint).Sub(position.BorrowShares, sharesToBurn)

	// Get market's positions tree and update position
	marketPositionsInterface, exists := positions.Get(marketId)
	if !exists {
		panic(ErrMarketNotCreated)
	}
	marketPositions := marketPositionsInterface.(*avl.Tree)
	marketPositions.Set(caller.String(), position)

	// Update market state
	market.TotalBorrowShares = new(u256.Uint).Sub(market.TotalBorrowShares, sharesToBurn)
	market.TotalBorrowAssets = new(u256.Uint).Sub(market.TotalBorrowAssets, assetsU256)
	markets.Set(marketId, market)

	// Handle token transfer using GRC20 interface
	tokenTeller := GetTokenCallerTeller(params.GetLoanToken())
	if err := tokenTeller.TransferFrom(caller, std.CurrentRealm().Address(), assetsU256.Uint64()); err != nil {
		panic(err)
	}

	emitRepay(marketId, caller, assetsU256, sharesToBurn)
}

/* COLLATERAL MANAGEMENT */

// SupplyCollateral supplies collateral to a market
// The collateral can be used to borrow assets from the market
func SupplyCollateral(marketId string, amount uint64) {
	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	caller := std.PreviousRealm().Address()

	_, params := GetMarket(marketId)

	// Get user's current position
	position := GetPosition(marketId, caller.String())

	// Update position
	position.Collateral = new(u256.Uint).Add(position.Collateral, u256.NewUint(amount))

	// Get market's positions tree and update position
	marketPositionsInterface, _ := positions.Get(marketId)
	marketPositions := marketPositionsInterface.(*avl.Tree)
	marketPositions.Set(caller.String(), position)

	// Handle token transfer using GRC20 interface
	tokenTeller := GetTokenCallerTeller(params.GetCollateralToken())
	if err := tokenTeller.TransferFrom(caller, std.CurrentRealm().Address(), amount); err != nil {
		panic(err)
	}

	emitSupplyCollateral(marketId, caller, amount)
}

// WithdrawCollateral withdraws collateral from a market
// The withdrawal will fail if it would make the user's position unhealthy
func WithdrawCollateral(marketId string, amount uint64) {
	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	caller := std.PreviousRealm().Address()

	_, params := GetMarket(marketId)

	// Accrue interest before any state changes
	accrueInterest(marketId)

	// Get user's current position
	position := GetPosition(marketId, caller.String())

	// Convert amount to uint256
	amountU256 := u256.NewUint(amount)

	// Check if user has enough collateral
	if amountU256.Gt(position.Collateral) {
		panic(ErrInsufficientCollateral)
	}

	println("position collateral before:", position.Collateral.ToString())

	// Update position
	position.Collateral = new(u256.Uint).Sub(position.Collateral, amountU256)

	// Get market's positions tree and update position
	marketPositionsInterface, exists := positions.Get(marketId)
	if !exists {
		panic(ErrMarketNotCreated)
	}
	marketPositions := marketPositionsInterface.(*avl.Tree)
	marketPositions.Set(caller.String(), position)

	// Check if position would still be healthy after withdrawal
	if !position.BorrowShares.IsZero() {
		if !isHealthy(marketId, caller.String()) {
			panic(ErrExceedsLTV)
		}
	}

	// Handle token transfer using GRC20 interface
	tokenTeller := GetTokenCallerTeller(params.GetCollateralToken())
	if err := tokenTeller.Transfer(caller, amount); err != nil {
		panic(err)
	}

	emitWithdrawCollateral(marketId, caller, amount)
}

/* LIQUIDATION */

// Liquidate liquidates a position that is below the liquidation threshold.
// It takes either seizedAssets (collateral to seize) or repaidShares (debt to repay), but not both.
func Liquidate(marketId string, borrower std.Address, seizedAssets, repaidShares uint64) (uint64, uint64) {
	// Check that exactly one of seizedAssets or repaidShares is non-zero
	if (seizedAssets == 0) == (repaidShares == 0) {
		panic(ErrInconsistentAmount)
	}

	// Get market data
	market, params := GetMarket(marketId)

	// Convert inputs to uint256
	seizedAssetsU256 := u256.NewUint(seizedAssets)
	repaidSharesU256 := u256.NewUint(repaidShares)

	// Accrue interest before making state changes
	accrueInterest(marketId)

	// Get borrower's position
	borrowerPos := GetPosition(marketId, borrower.String())

	// Get collateral price from oracle
	collateralPrice, err := GetPrice(marketId)
	if err != nil {
		panic(err)
	}

	// Check if position is unhealthy
	if isHealthy(marketId, borrower.String()) {
		panic(ErrHealthyPosition)
	}

	// Calculate the liquidation incentive factor: min(maxLiquidationIncentiveFactor, 1/(1 - cursor*(1 - lltv)))
	incentiveFactor := WDivDown(
		WAD,
		new(u256.Uint).Sub(WAD, WMulDown(LIQUIDATION_CURSOR, new(u256.Uint).Sub(WAD, params.LLTV))),
	)
	incentiveFactor = Min(incentiveFactor, MAX_LIQUIDATION_INCENTIVE_FACTOR)

	// Calculate seized assets or repaid shares based on input
	if seizedAssets > 0 {
		// Calculate repaid shares from seized assets
		seizedAssetsQuoted := MulDivUp(seizedAssetsU256, collateralPrice, ORACLE_PRICE_SCALE)
		repaidSharesU256 = ToSharesUp(
			WDivUp(seizedAssetsQuoted, incentiveFactor),
			market.TotalBorrowAssets,
			market.TotalBorrowShares,
		)
	} else {
		// Calculate seized assets from repaid shares
		seizedAssetsU256 = MulDivDown(
			WMulDown(
				ToAssetsDown(
					repaidSharesU256,
					market.TotalBorrowAssets,
					market.TotalBorrowShares,
				),
				incentiveFactor,
			),
			ORACLE_PRICE_SCALE,
			collateralPrice,
		)
	}

	// Calculate repaid assets
	repaidAssets := ToAssetsUp(
		repaidSharesU256,
		market.TotalBorrowAssets,
		market.TotalBorrowShares,
	)

	// Update borrower's position
	borrowerPos.BorrowShares = new(u256.Uint).Sub(borrowerPos.BorrowShares, repaidSharesU256)
	borrowerPos.Collateral = new(u256.Uint).Sub(borrowerPos.Collateral, seizedAssetsU256)

	// Update market state
	market.TotalBorrowShares = new(u256.Uint).Sub(market.TotalBorrowShares, repaidSharesU256)
	market.TotalBorrowAssets = new(u256.Uint).Sub(market.TotalBorrowAssets, repaidAssets)
	markets.Set(marketId, market)

	// Handle bad debt if all collateral is seized
	if borrowerPos.Collateral.IsZero() {
		badDebtShares := borrowerPos.BorrowShares
		badDebtAssets := ToAssetsUp(
			badDebtShares,
			market.TotalBorrowAssets,
			market.TotalBorrowShares,
		)
		if badDebtAssets.Cmp(market.TotalBorrowAssets) > 0 {
			badDebtAssets = market.TotalBorrowAssets
		}

		market.TotalBorrowAssets = new(u256.Uint).Sub(market.TotalBorrowAssets, badDebtAssets)
		market.TotalSupplyAssets = new(u256.Uint).Sub(market.TotalSupplyAssets, badDebtAssets)
		market.TotalBorrowShares = new(u256.Uint).Sub(market.TotalBorrowShares, badDebtShares)
		borrowerPos.BorrowShares = u256.Zero()
	}

	// Transfer seized collateral to liquidator
	caller := std.PreviousRealm().Address()
	tokenTeller := GetTokenCallerTeller(params.GetCollateralToken())
	if err := tokenTeller.Transfer(caller, seizedAssetsU256.Uint64()); err != nil {
		panic(err)
	}

	// Transfer repaid assets from liquidator to contract
	tokenTeller = GetTokenCallerTeller(params.GetLoanToken())
	if err := tokenTeller.TransferFrom(caller, std.CurrentRealm().Address(), repaidAssets.Uint64()); err != nil {
		panic(err)
	}

	// Emit liquidate event
	emitLiquidate(marketId, caller, borrower, repaidAssets, repaidSharesU256, seizedAssetsU256)

	return seizedAssetsU256.Uint64(), repaidAssets.Uint64()
}

/* INTEREST ACCRUAL */

func AccrueInterest(marketId string) {
	// Check if market exists
	if _, exists := markets.Get(marketId); !exists {
		panic(ErrMarketNotCreated)
	}

	accrueInterest(marketId)
}

// accrueInterest accrues interest for a market using its IRM
func accrueInterest(marketId string) {
	market, params := GetMarket(marketId)

	// Calculate elapsed time
	now := time.Now().Unix()
	elapsed := now - market.LastUpdate

	println("elapsed:", elapsed)
	if elapsed == 0 {
		return
	}

	// Skip if no IRM or no borrows
	if params.IRM == "" || market.TotalBorrowAssets.IsZero() {
		market.LastUpdate = now
		markets.Set(marketId, market)
		return
	}

	// Get borrow rate from IRM (already WAD-scaled and per second)
	irm := GetIRM(params.IRM)
	borrowRate := irm.BorrowRate(market.TotalSupplyAssets, market.TotalBorrowAssets)

	println("borrowRate:", borrowRate.ToString())

	// Calculate accrued interest using Taylor series approximation of e^(rate * time) - 1
	// wTaylorCompounded returns the sum of first 3 terms: x*n + (x*n)^2/2 + (x*n)^3/6
	// This approximates continuous compound interest more accurately than simple interest
	elapsedUint := u256.NewUint(uint64(elapsed))
	wtc := WTaylorCompounded(borrowRate, elapsedUint)

	println("wtc:", wtc.ToString())
	interest := WMulDown(market.TotalBorrowAssets, wtc)

	println("interest:", interest.ToString())

	println("market.TotalBorrowAssets:", market.TotalBorrowAssets.ToString())

	// Update market state
	market.TotalBorrowAssets = new(u256.Uint).Add(market.TotalBorrowAssets, interest)
	market.TotalSupplyAssets = new(u256.Uint).Add(market.TotalSupplyAssets, interest)

	// Handle fees if any
	if !market.Fee.IsZero() && feeRecipient != "" {
		// Calculate fee amount
		feeAmount := WMulDown(interest, market.Fee)

		// Calculate fee shares
		// The fee amount is subtracted from total supply to compensate for already increased supply
		totalSupplyMinusFee := new(u256.Uint).Sub(market.TotalSupplyAssets, feeAmount)
		feeShares := ToSharesDown(
			feeAmount,
			totalSupplyMinusFee,
			market.TotalSupplyShares,
		)

		// Update fee recipient's position
		feeRecipientPos := GetPosition(marketId, feeRecipient.String())
		feeRecipientPos.SupplyShares = new(u256.Uint).Add(feeRecipientPos.SupplyShares, feeShares)
		marketPositionsInterface, _ := positions.Get(marketId)
		marketPositions := marketPositionsInterface.(*avl.Tree)
		marketPositions.Set(feeRecipient.String(), feeRecipientPos)

		market.TotalSupplyShares = new(u256.Uint).Add(market.TotalSupplyShares, feeShares)
	}

	market.LastUpdate = now
	markets.Set(marketId, market)

	emitAccrueInterest(marketId, borrowRate, interest)
}

/* HEALTH CALCULATIONS */

// isHealthy checks if a position's health factor is above 1
// Returns true if:
// 1. The user has no borrows, or
// 2. The user's collateral value * LLTV >= borrowed value
func isHealthy(marketId string, userAddr string) bool {
	position := GetPosition(marketId, userAddr)

	// If no borrows, position is healthy
	if position.BorrowShares.IsZero() {
		return true
	}

	market, params := GetMarket(marketId)

	// Calculate current borrowed value
	borrowed := ToAssetsUp(
		position.BorrowShares,
		market.TotalBorrowAssets,
		market.TotalBorrowShares,
	)

	collateralPrice, err := GetPrice(params.PoolPath)
	if err != nil {
		panic(err)
	}

	// Calculate max borrow allowed
	maxBorrow := WMulDown(MulDivDown(position.Collateral, collateralPrice, ORACLE_PRICE_SCALE), params.LLTV)

	println("maxBorrow:", maxBorrow.ToString())
	println("borrowed:", borrowed.ToString())

	// Position is healthy if borrowed <= maxBorrow
	return borrowed.Cmp(maxBorrow) <= 0
}
