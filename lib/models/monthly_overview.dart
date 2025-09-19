class MonthlyOverview {
  final String monthYear; // yyyy-MM
  final double totalSales;
  final double netProfit;
  final double cashSales;
  final double creditSales;
  final double totalReturns;
  final double totalDebtPayments;
  final double settlementAdditions;
  final double settlementReturns;

  const MonthlyOverview({
    required this.monthYear,
    required this.totalSales,
    required this.netProfit,
    required this.cashSales,
    required this.creditSales,
    required this.totalReturns,
    required this.totalDebtPayments,
    required this.settlementAdditions,
    required this.settlementReturns,
  });
}


