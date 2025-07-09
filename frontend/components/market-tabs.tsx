"use client"

import { MarketInfo, Position } from "@/app/types"
import { MarketOverview } from "@/components/market-overview"
import { MyPosition } from "@/components/my-position"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { DataTable } from "./ui/data-table"
import { activityColumns } from "./activity-columns"
import { useQuery } from '@tanstack/react-query';
import { getMarketActivity } from '@/app/services/api.service';

interface MarketTabsProps {
  market: MarketInfo;
  apyVariations: {
    sevenDay: number;
    ninetyDay: number;
  };
  cardStyles: string;
  healthFactor: string;
  currentCollateral: number;
  currentLoan: number;
  positionData?: Position | null;
}

export function MarketTabs({ 
  market, 
  apyVariations, 
  cardStyles,
  healthFactor,
  currentCollateral,
  currentLoan,
  positionData
}: MarketTabsProps) {

  const { data: marketActivity = [] } = useQuery({
    queryKey: ['marketActivity', market.poolPath],
    queryFn: () => getMarketActivity(market.poolPath!),
    enabled: !!market.poolPath
  });

  return (
    <Tabs defaultValue="overview" className="w-full">
      <TabsList className="mb-6 border-b border-gray-700/50 w-full bg-transparent p-0 h-auto flex flex-row justify-start">
        <TabsTrigger 
          value="overview" 
          className="bg-transparent px-6 py-3 text-gray-400 hover:bg-transparent data-[state=active]:text-midnightPurple-500 data-[state=active]:bg-transparent data-[state=active]:border-b-1 data-[state=active]:border-midnightPurple-500 rounded-none transition-all"
        >
          Market Overview
        </TabsTrigger>
        <TabsTrigger 
          value="position" 
          className="bg-transparent px-6 py-3 text-gray-400 hover:bg-transparent data-[state=active]:text-midnightPurple-500 data-[state=active]:bg-transparent data-[state=active]:border-b-1 data-[state=active]:border-midnightPurple-500 rounded-none transition-all"
        >
          My Position
        </TabsTrigger>
        <TabsTrigger 
          value="activity" 
          className="bg-transparent px-6 py-3 text-gray-400 hover:bg-transparent data-[state=active]:text-midnightPurple-500 data-[state=active]:bg-transparent data-[state=active]:border-b-1 data-[state=active]:border-midnightPurple-500 rounded-none transition-all"
        >
          Activity
        </TabsTrigger>
      </TabsList>
      
      <TabsContent value="overview" className="mt-0">
        <MarketOverview 
          market={market} 
          apyVariations={apyVariations} 
          cardStyles={cardStyles}
        />
      </TabsContent>
      
      <TabsContent value="position" className="mt-0">
        <MyPosition
          market={market}
          cardStyles={cardStyles}
          healthFactor={healthFactor}
          currentCollateral={currentCollateral}
          currentLoan={currentLoan}
          positionData={positionData}
        />
      </TabsContent>

      <TabsContent value="activity" className="mt-0">
        <DataTable columns={activityColumns} data={marketActivity} className="w-full h-full mt-0" />
      </TabsContent>
    </Tabs>
  )
} 
