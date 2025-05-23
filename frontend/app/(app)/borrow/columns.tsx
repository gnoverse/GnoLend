"use client"

import { MarketInfo } from "@/app/types"
import { formatLTV, formatRate, parseTokenAmount } from "@/app/utils/format.utils"
import { Button } from "@/components/ui/button"
import { ColumnDef } from "@tanstack/react-table"
import { ArrowUpDown } from "lucide-react"

export const columns: ColumnDef<MarketInfo>[] = [
  {
    accessorKey: "loanTokenSymbol",
    header: () => {
      return (
        <div className="text-left px-3">Loan Asset</div>
      )
    },
    cell: ({ row }) => {
      const loanSymbol = row.original.loanTokenSymbol
      
      return (
        <div className="flex items-center text-left px-3">
          <span className="font-medium">{loanSymbol}</span>
        </div>
      )
    },
  },
  {
    accessorKey: "collateralTokenSymbol",
    header: () => {
      return (
        <div className="text-left px-3">Collateral Asset</div>
      )
    },
    cell: ({ row }) => {
      const collateralSymbol = row.original.collateralTokenSymbol
      
      return (
        <div className="flex items-center text-left px-3">
          <span className="font-medium">{collateralSymbol}</span>
        </div>
      )
    },
  },
  {
    accessorKey: "totalSupplyAssets",
    header: ({ column }) => {
      return (
        <div className="flex justify-start">
          <Button
            variant="ghost"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            Total Supply
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        </div>
      )
    },
    cell: ({ row }) => {
      return <div className="text-left font-medium px-3">{parseTokenAmount(row.original.totalSupplyAssets, row.original.loanTokenDecimals)} {row.original.loanTokenSymbol}</div>
    },
  },
  {
    accessorKey: "totalBorrowAssets",
    header: ({ column }) => {
      return (
        <div className="flex justify-start">
          <Button
            variant="ghost"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            Total Borrow
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        </div>
      )
    },
    cell: ({ row }) => {
      return <div className="text-left font-medium px-3">{parseTokenAmount(row.original.totalBorrowAssets, row.original.loanTokenDecimals)} {row.original.loanTokenSymbol}</div>
    },
  },
  {
    accessorKey: "apy",
    header: ({ column }) => {
      return (
        <div className="flex justify-start">
          <Button
            variant="ghost"
            onClick={() => column.toggleSorting(column.getIsSorted() === "asc")}
          >
            APR
            <ArrowUpDown className="ml-2 h-4 w-4" />
          </Button>
        </div>
      )
    },
    cell: ({ row }) => {
      return <div className="text-left font-medium px-3">{formatRate(row.original.borrowAPR, 18, true)}</div>
    },
  },
  {
    accessorKey: "lltv",
    header: () => {
      return <div className="text-left">Max LTV</div>
    },
    cell: ({ row }) => {
      return <div className="text-left font-medium">{formatLTV(row.original.lltv)}</div>
    },
  },
] 
