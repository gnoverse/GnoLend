import { z } from "zod";

const Uint256Schema = z.string().regex(/^\d+$/, {
  message: "Must be a valid uint256 string representation",
});

export const PositionSchema = z.object({
  supplyShares: Uint256Schema,
  borrowShares: Uint256Schema,
  collateral: Uint256Schema,
});

export type Position = z.infer<typeof PositionSchema>;

export const MarketSchema = z.object({
  totalSupplyAssets: Uint256Schema,
  totalSupplyShares: Uint256Schema,
  totalBorrowAssets: Uint256Schema,
  totalBorrowShares: Uint256Schema,
  lastUpdate: z.number().int(),
  fee: Uint256Schema,
});

export type Market = z.infer<typeof MarketSchema>;

export const MarketParamsSchema = z.object({
  poolPath: z.string(),
  irm: z.string(),
  lltv: Uint256Schema,
  isToken0Loan: z.boolean(),
});

export type MarketParams = z.infer<typeof MarketParamsSchema>;

// Updated to match RpcMarketInfo structure from json.gno
export const MarketInfoSchema = z.object({
  // Market fields
  totalSupplyAssets: Uint256Schema,
  totalSupplyShares: Uint256Schema,
  totalBorrowAssets: Uint256Schema,
  totalBorrowShares: Uint256Schema,
  lastUpdate: z.number().int(),
  fee: Uint256Schema,
  
  // Params fields
  poolPath: z.string(),
  irm: z.string(),
  lltv: Uint256Schema,
  isToken0Loan: z.boolean(),
  
  // Additional fields
  loanToken: z.string(),
  collateralToken: z.string(),
  currentPrice: z.string(),
  borrowAPR: Uint256Schema,
  supplyAPR: Uint256Schema,
  utilization: Uint256Schema,
  
  // Token information fields
  loanTokenName: z.string(),
  loanTokenSymbol: z.string(),
  loanTokenDecimals: z.number().int(),
  
  collateralTokenName: z.string(),
  collateralTokenSymbol: z.string(),
  collateralTokenDecimals: z.number().int(),
  
  marketId: z.string().optional(), //todo when implemented
});

export type MarketInfo = z.infer<typeof MarketInfoSchema>;

// -------------- listing responses & parsing functions for them

export const ApiListMarketsResponseSchema = z.object({
  markets: z.array(
    z.record(z.string(), MarketSchema)
  ),
});

export type ApiListMarketsResponse = z.infer<typeof ApiListMarketsResponseSchema>;

export const ApiListMarketsInfoResponseSchema = z.array(
  z.record(z.string(), MarketInfoSchema)
);

export type ApiListMarketsInfoResponse = z.infer<typeof ApiListMarketsInfoResponseSchema>;

export const LoanAmountSchema = z.object({
  amount: z.string(),
});
export type LoanAmount = z.infer<typeof LoanAmountSchema>;

export const UserLoanSchema = z.object({
  token: z.string(),
  amount: z.string(),
});
export const UserLoansSchema = z.array(UserLoanSchema);
export type UserLoan = z.infer<typeof UserLoanSchema>;
export type UserLoans = z.infer<typeof UserLoansSchema>;

export const HealthFactorSchema = z.object({
  healthFactor: z.string(),
});
export type HealthFactor = z.infer<typeof HealthFactorSchema>; 

export function parseAndValidateJson<T>(jsonString: string, schema: z.ZodType<T>): T {
  try {
    const parsed = JSON.parse(jsonString);
    return schema.parse(parsed);
  } catch (error) {
    if (error instanceof z.ZodError) {
      console.error("Validation error:", error.format());
    } else {
      console.error("JSON parsing error:", error);
    }
    throw error;
  }
}

export function parseValidatedMarketsList(jsonString: string): ApiListMarketsResponse {
  return parseAndValidateJson(jsonString, ApiListMarketsResponseSchema);
}

export function parseValidatedMarketsInfoList(jsonString: string): ApiListMarketsInfoResponse {
  return parseAndValidateJson(jsonString, ApiListMarketsInfoResponseSchema);
}