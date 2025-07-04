// server component - SSR
import { apiGetMarketInfo } from '@/app/services/abci';
import { getMarketActivity } from '@/app/services/indexer/historic';
import { getNetBorrowHistory, getNetSupplyHistory, getUtilizationHistory } from '@/app/services/backend/historic';
import { getHistoryForMarket } from '../mock-history';
import { MarketPageClient } from './client-page';

export default async function MarketPage({ params }: { params: Promise<{ marketId: string }> }) {
  const { marketId } = await params;
  const decodedMarketId = decodeURIComponent(marketId);
  
  const [marketInfo, mockHistory, netSupplyHistory, netBorrowHistory, marketActivity, utilizationHistory] = await Promise.all([
    apiGetMarketInfo(decodedMarketId),
    getHistoryForMarket(decodedMarketId), // targeting through ssr/historic.ts
    getNetSupplyHistory(decodedMarketId), // ^
    getNetBorrowHistory(decodedMarketId), // ^
    getMarketActivity(decodedMarketId), // targeting through indexer/historic.ts directly
    getUtilizationHistory(decodedMarketId) // ssr/historic.ts
  ]);

  const apyVariations = {
    sevenDay: 0,
    ninetyDay: 0
  };
  
  return (
    <MarketPageClient 
      marketId={decodedMarketId}
      marketInfo={marketInfo}
      mockHistory={mockHistory}
      netSupplyHistory={netSupplyHistory}
      netBorrowHistory={netBorrowHistory}
      marketActivity={marketActivity}
      apyVariations={apyVariations}
      utilizationHistory={utilizationHistory}
    />
  );
}
