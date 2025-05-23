import {
    ApiListMarketsInfoResponse,
    ApiListMarketsInfoResponseSchema,
    ApiListMarketsResponse,
    ApiListMarketsResponseSchema,
    HealthFactor,
    HealthFactorSchema,
    LoanAmount,
    LoanAmountSchema,
    Market,
    MarketInfo,
    MarketInfoSchema,
    MarketParams,
    MarketParamsSchema,
    MarketSchema,
    Position,
    PositionSchema,
    UserLoans,
    UserLoansSchema,
} from "../types"
import { parseStringResult, parseValidatedJsonResult } from "../utils/parsing.utils"
import { GnoService } from "./abci.service"

const REALM_PATH = "gno.land/r/gnolend"
const gnoService = GnoService.getInstance()

// GNO LEND API QUERIES

export async function apiGetMarket(marketId: string): Promise<Market> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetMarket("${marketId}")`,
    )
    return parseValidatedJsonResult(result, MarketSchema)
  } catch (error) {
    console.error('Error fetching market API data:', error)
    throw error
  }
}

export async function apiGetMarketParams(marketId: string): Promise<MarketParams> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetMarketParams("${marketId}")`,
    )
    return parseValidatedJsonResult(result, MarketParamsSchema)
  } catch (error) {
    console.error('Error fetching market params API data:', error)
    throw error
  }
}

export async function apiGetPosition(marketId: string, userAddr: string): Promise<Position> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetPosition("${marketId}", "${userAddr}")`,
    )
    return parseValidatedJsonResult(result, PositionSchema)
  } catch (error) {
    console.error('Error fetching position API data:', error)
    throw error
  }
}

export async function apiListMarkets(): Promise<ApiListMarketsResponse> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiListMarkets()`,
    )
    return parseValidatedJsonResult(result, ApiListMarketsResponseSchema)
  } catch (error) {
    console.error('Error fetching markets list API data:', error)
    throw error
  }
}

export async function apiGetMarketInfo(marketId: string): Promise<MarketInfo> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetMarketInfo("${marketId}")`,
    )
    return parseValidatedJsonResult(result, MarketInfoSchema)
  } catch (error) {
    console.error('Error fetching market info:', error)
    throw error
  }
}

export async function apiListMarketsInfo(): Promise<ApiListMarketsInfoResponse> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiListMarketsInfo()`,
    )
    return parseValidatedJsonResult(result, ApiListMarketsInfoResponseSchema)
  } catch (error) {
    console.error('Error fetching markets info list:', error)
    throw error
  }
}

export async function getFeeRecipient(): Promise<string> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `GetFeeRecipient()`,
    )
    return parseStringResult(result)
  } catch (error) {
    console.error('Error fetching fee recipient:', error)
    throw error
  }
}

export async function apiGetLoanAmount(marketId: string, user: string): Promise<LoanAmount> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetLoanAmount("${marketId}", "${user}")`,
    )
    return parseValidatedJsonResult(result, LoanAmountSchema)
  } catch (error) {
    console.error('Error fetching loan amount:', error)
    throw error
  }
}

export async function apiGetUserLoans(user: string): Promise<UserLoans> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetUserLoans("${user}")`,
    )
    return parseValidatedJsonResult(result, UserLoansSchema)
  } catch (error) {
    console.error('Error fetching user loans:', error)
    throw error
  }
}

export async function apiGetHealthFactor(marketId: string, userAddr: string): Promise<HealthFactor> {
  try {
    const result = await gnoService.evaluateExpression(
      REALM_PATH,
      `ApiGetHealthFactor("${marketId}", "${userAddr}")`,
    )
    return parseValidatedJsonResult(result, HealthFactorSchema)
  } catch (error) {
    console.error('Error fetching health factor:', error)
    throw error
  }
}
