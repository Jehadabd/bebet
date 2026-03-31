// lib/models/invoice_prediction.dart
// نماذج التوقعات الذكية للفواتير

class InvoicePrediction {
  final String type; // 'last_similar', 'frequent', 'smart'
  final String title;
  final List<PredictedItem> items;
  final double totalAmount;
  final double score;
  final String? description;

  InvoicePrediction({
    required this.type,
    required this.title,
    required this.items,
    required this.totalAmount,
    required this.score,
    this.description,
  });
}

class PredictedItem {
  final int? productId;
  final String productName;
  final double quantity;
  final double price;
  final String saleType;
  final double confidence;

  PredictedItem({
    this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    required this.saleType,
    required this.confidence,
  });
}
