package service

import (
	"encoding/json"
	"strconv"
	"volos-backend/indexer"
)

type MarketActivity struct {
	Type             string  `json:"type"`
	Amount           float64 `json:"amount"`
	Caller           string  `json:"caller"`
	Hash             string  `json:"hash"`
	Timestamp        string  `json:"timestamp"`
	IsAmountInShares bool    `json:"isAmountInShares"`
}

// GetMarketActivity fetches all activity transactions (deposits, withdraws, borrows, repays, etc.) for a given marketId from the indexer.
//
// NOTE: This function currently retrieves ALL transactions for the given market, which can become a very large number very quickly as the market grows.
//
// For scalability, time-based or block height-based pagination should be implemented in the future.
// Retrieving the last X transactions directly is not possible with the current API, so a solution for efficient pagination or limiting must be considered.
func GetMarketActivity(marketId string) ([]MarketActivity, error) {
	qb := indexer.NewQueryBuilder("getMarketActivity", indexer.MarketActivityFields)
	qb.Where().MarketId(marketId)
	resp, err := qb.Execute()
	if err != nil {
		return nil, err
	}
	var data struct {
		Data struct {
			GetTransactions []map[string]interface{} `json:"getTransactions"`
		} `json:"data"`
	}
	json.Unmarshal(resp, &data)

	var raw []struct {
		Type             string
		Amount           float64
		Caller           string
		Hash             string
		BlockHeight      int64
		IsAmountInShares bool
	}

	for _, tx := range data.Data.GetTransactions {
		parsedTx := parseMarketActivity(tx)
		raw = append(raw, parsedTx)
	}

	var heights []int64
	for _, tx := range raw {
		heights = append(heights, tx.BlockHeight)
	}
	heightToTime, err := FetchBlockTimestamps(heights)
	if err != nil {
		return nil, err
	}

	var result []MarketActivity
	for _, tx := range raw {
		result = append(result, MarketActivity{
			Type:             tx.Type,
			Amount:           tx.Amount,
			Caller:           tx.Caller,
			Hash:             tx.Hash,
			Timestamp:        heightToTime[tx.BlockHeight],
			IsAmountInShares: tx.IsAmountInShares,
		})
	}
	return result, nil
}

// Helper to parse a single transaction map into a rawTx-like struct, updating heightSet
func parseMarketActivity(tx map[string]interface{}) struct {
	Type             string
	Amount           float64
	Caller           string
	Hash             string
	BlockHeight      int64
	IsAmountInShares bool
} {
	defer func() {
		if r := recover(); r != nil {
			// return default values if panic occurs
		}
	}()

	blockHeight := int64(tx["block_height"].(float64))

	hash := tx["hash"].(string)
	messages := tx["messages"].([]interface{})
	caller := messages[0].(map[string]interface{})["value"].(map[string]interface{})["caller"].(string)

	response := tx["response"].(map[string]interface{})
	eventsArr := response["events"].([]interface{})

	txType := ""
	amount := 0.0
	isAmountInShares := false

	for _, ev := range eventsArr {
		evMap := ev.(map[string]interface{})
		txType = evMap["type"].(string)
		attrs := evMap["attrs"].([]interface{})
		for _, attr := range attrs {
			attrMap := attr.(map[string]interface{})
			key := attrMap["key"].(string)
			if key == "amount" || key == "assets" || key == "shares" {
				value := attrMap["value"].(string)
				if val, err := strconv.ParseFloat(value, 64); err == nil && val != 0 {
					amount = val
					if key == "shares" {
						isAmountInShares = true
					}
				}
			}
		}
	}

	return struct {
		Type             string
		Amount           float64
		Caller           string
		Hash             string
		BlockHeight      int64
		IsAmountInShares bool
	}{
		Type:             txType,
		Amount:           amount,
		Caller:           caller,
		Hash:             hash,
		BlockHeight:      blockHeight,
		IsAmountInShares: isAmountInShares,
	}
}
