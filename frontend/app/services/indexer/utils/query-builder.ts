import axios from "axios";
import {
  UNIVERSAL_TRANSACTION_FIELDS
} from './fields.indexer';
import { parseTransactions } from "./parsing";
import { GraphQLResponse } from './types.indexer';

// start tx indexer for gnodev on port 3100:
// /build/tx-indexer start --remote http://localhost:26657 --db-path indexer-db --listen-address localhost:3100

// const txIndexerUrl = "https://indexer.test6.testnets.gno.land"
const txIndexerUrl = "http://localhost:3100"

export class QueryBuilder {
  private operationName: string;
  private whereBuilder: WhereClauseBuilder;
  private fields: string;

  constructor(operationName: string, fields: string = UNIVERSAL_TRANSACTION_FIELDS) {
    this.operationName = operationName;
    this.fields = fields;
    this.whereBuilder = new WhereClauseBuilder(this);
  }

  where(): WhereClauseBuilder {
    return this.whereBuilder;
  }

  useFields(fields: string): QueryBuilder {
    this.fields = fields;
    return this;
  }

  addFields(fields: string): QueryBuilder {
    this.fields += `\n          ${fields}`;
    return this;
  }

  build(): string {
    const whereClause = this.whereBuilder.build();
    return `
      query ${this.operationName} {
        getTransactions(
          where: {
            ${whereClause}
          }
        ) {
          ${this.fields}
        }
      }
    `;
  }

  async execute(variables?: Record<string, unknown>): Promise<GraphQLResponse> {
    const query = this.build();
    return await queryIndexer(query, this.operationName, variables) as GraphQLResponse;
  }

  async executeAndParse(
    options?: {
      filterByMarketId?: string;
      filterByEventTypes?: string[];
      includeAllEvents?: boolean;
    }
  ): Promise<ReturnType<typeof parseTransactions>> {
    const response = await this.execute();
    const transactions = response?.data?.getTransactions ?? [];
    return await parseTransactions(transactions, options);
  }

  async executeAndParseWithTimestamps(
    options?: {
      filterByMarketId?: string;
      filterByEventTypes?: string[];
      includeAllEvents?: boolean;
    }
  ): Promise<ReturnType<typeof parseTransactions>> {
    const response = await this.execute();
    const transactions = response?.data?.getTransactions ?? [];
    return await parseTransactions(transactions, options);
  }
}

export function buildQuery(operationName: string, fields?: string): QueryBuilder {
  return new QueryBuilder(operationName, fields);
}

export function buildUniversalQuery(
  operationName: string,
  whereClause: string,
  fields: string = UNIVERSAL_TRANSACTION_FIELDS
): string {
  return `
    query ${operationName} {
      getTransactions(
        where: {
          ${whereClause}
        }
      ) {
        ${fields}
      }
    }
  `
}

export class WhereClauseBuilder {
  private conditions: string[] = [];
  private eventConditions: string[] = [];
  private queryBuilder: QueryBuilder;

  constructor(queryBuilder: QueryBuilder) {
    this.queryBuilder = queryBuilder;
  }

  success(success: boolean = true): WhereClauseBuilder {
    this.conditions.push(`success: { eq: ${success} }`);
    return this;
  }
  
  blockHeightRange(min?: number, max?: number): WhereClauseBuilder {
    const conditions = [];
    if (min !== undefined) {
      conditions.push(`gt: ${min}`);
    }
    if (max !== undefined) {
      conditions.push(`lt: ${max}`);
    }
    if (conditions.length > 0) {
      this.conditions.push(`block_height: { ${conditions.join(', ')} }`);
    }
    return this;
  }
  
  eventType(eventType: string): WhereClauseBuilder {
    this.eventConditions.push(`type: { eq: "${eventType}" }`);
    return this;
  }
  
  marketId(marketId: string): WhereClauseBuilder {
    this.eventConditions.push(`attrs: { key: { eq: "market_id" }, value: { eq: "${marketId}" } }`);
    return this;
  }

  add(condition: string): WhereClauseBuilder {
    this.conditions.push(condition);
    return this;
  }

  build(): string {
    const allConditions = [...this.conditions];
    
    if (this.eventConditions.length > 0) {
      const eventCondition = `
        response: {
          events: {
            GnoEvent: {
              ${this.eventConditions.join('\n              ')}
            }
          }
        }
      `;
      allConditions.push(eventCondition);
    }
    
    return allConditions.filter(Boolean).join('\n          ');
  }

  reset(): WhereClauseBuilder {
    this.conditions = [];
    this.eventConditions = [];
    return this;
  }

  async execute(variables?: Record<string, unknown>): Promise<GraphQLResponse> {
    return this.queryBuilder.execute(variables);
  }

  async executeAndParse(
    options?: {
      filterByMarketId?: string;
      filterByEventTypes?: string[];
      includeAllEvents?: boolean;
    }
  ): Promise<ReturnType<typeof parseTransactions>> {
    return this.queryBuilder.executeAndParse(options);
  }
}

export function where(): WhereClauseBuilder {
  return new WhereClauseBuilder(new QueryBuilder("generic"));
}

export async function queryIndexer(
  query: string, 
  operationName: string, 
  variables?: Record<string, unknown>
): Promise<unknown> {
  try {
    const requestBody = { query, operationName, variables };
    
    const response = await axios.post(
      `${txIndexerUrl}/graphql/query`,
      requestBody,
      { headers: { 'Content-Type': 'application/json' } }
    )

    return response.data
  } catch (error) {
    console.error('Indexer query failed:', error)
    if (axios.isAxiosError(error)) {
      console.error('Response data:', error.response?.data);
      console.error('Response status:', error.response?.status);
    }
    throw error
  }
}