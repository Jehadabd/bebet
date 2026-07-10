/// أداة تقريب الأسعار إلى أقرب فئة عملة عراقية صالحة
/// أقل فئة عملة متداولة في العراق هي 250 دينار
class PriceRounder {
  /// تقريب السعر إلى أقرب 250 دينار عراقي
  /// مثال: 1150 → 1250, 1100 → 1000, 1375 → 1500, 2600 → 2500
  static double roundToNearest250(double price) {
    if (price <= 0) return 0;
    return (price / 250).round() * 250.0;
  }

  /// تقريب السعر إلى أعلى 250 دينار عراقي
  /// مثال: 1100 → 1250, 1250 → 1250, 1251 → 1500
  static double ceilToNearest250(double price) {
    if (price <= 0) return 0;
    return (price / 250).ceil() * 250.0;
  }

  /// تقريب السعر إلى أدنى 250 دينار عراقي
  /// مثال: 1400 → 1250, 1250 → 1250, 1251 → 1250
  static double floorToNearest250(double price) {
    if (price <= 0) return 0;
    return (price / 250).floor() * 250.0;
  }
}
