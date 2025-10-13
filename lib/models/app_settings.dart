import 'package:flutter/material.dart';
import 'font_settings.dart';

class AppSettings {
  final List<String> phoneNumbers;
  final int remainingAmountColor;
  final int discountColor;
  final int loadingFeesColor;
  final int totalBeforeDiscountColor;
  final int totalAfterDiscountColor;
  final int previousDebtColor;
  final int currentDebtColor;
  final int electricPhoneColor;
  final int healthPhoneColor;
  final int companyDescriptionColor;
  final String companyDescription;
  final int companyNameColor;
  final int itemSerialColor;
  final int itemDetailsColor;
  final int itemQuantityColor;
  final int itemPriceColor;
  final int itemTotalColor;
  final int noticeColor;
  final int paidAmountColor;
  final FontSettings fontSettings;

  AppSettings({
    this.phoneNumbers = const [],
    int? remainingAmountColor,
    int? discountColor,
    int? loadingFeesColor,
    int? totalBeforeDiscountColor,
    int? totalAfterDiscountColor,
    int? previousDebtColor,
    int? currentDebtColor,
    int? electricPhoneColor,
    int? healthPhoneColor,
    int? companyDescriptionColor,
    String? companyDescription,
    int? companyNameColor,
    int? itemSerialColor,
    int? itemDetailsColor,
    int? itemQuantityColor,
    int? itemPriceColor,
    int? itemTotalColor,
    int? noticeColor,
    int? paidAmountColor,
    FontSettings? fontSettings,
  }) : remainingAmountColor = remainingAmountColor ?? Colors.black.value,
       discountColor = discountColor ?? Colors.black.value,
       loadingFeesColor = loadingFeesColor ?? Colors.black.value,
       totalBeforeDiscountColor = totalBeforeDiscountColor ?? Colors.black.value,
       totalAfterDiscountColor = totalAfterDiscountColor ?? Colors.black.value,
       previousDebtColor = previousDebtColor ?? Colors.black.value,
       currentDebtColor = currentDebtColor ?? Colors.black.value,
       electricPhoneColor = electricPhoneColor ?? Colors.black.value,
       healthPhoneColor = healthPhoneColor ?? Colors.black.value,
       companyDescriptionColor = companyDescriptionColor ?? Colors.black.value,
       companyDescription = companyDescription ?? 'لتجارة المواد الكهربائية والكيبلات و العدداليدوية والصحية',
       companyNameColor = companyNameColor ?? Colors.green.value,
       itemSerialColor = itemSerialColor ?? Colors.black.value,
       itemDetailsColor = itemDetailsColor ?? Colors.black.value,
       itemQuantityColor = itemQuantityColor ?? Colors.black.value,
       itemPriceColor = itemPriceColor ?? Colors.black.value,
       itemTotalColor = itemTotalColor ?? Colors.black.value,
       noticeColor = noticeColor ?? Colors.red.value,
       paidAmountColor = paidAmountColor ?? Colors.black.value,
       fontSettings = fontSettings ?? FontSettings();

  Map<String, dynamic> toJson() => {
        'phoneNumbers': phoneNumbers,
        'remainingAmountColor': remainingAmountColor,
        'discountColor': discountColor,
        'loadingFeesColor': loadingFeesColor,
        'totalBeforeDiscountColor': totalBeforeDiscountColor,
        'totalAfterDiscountColor': totalAfterDiscountColor,
        'previousDebtColor': previousDebtColor,
        'currentDebtColor': currentDebtColor,
        'electricPhoneColor': electricPhoneColor,
        'healthPhoneColor': healthPhoneColor,
        'companyDescriptionColor': companyDescriptionColor,
        'companyDescription': companyDescription,
        'companyNameColor': companyNameColor,
        'itemSerialColor': itemSerialColor,
        'itemDetailsColor': itemDetailsColor,
        'itemQuantityColor': itemQuantityColor,
        'itemPriceColor': itemPriceColor,
        'itemTotalColor': itemTotalColor,
        'noticeColor': noticeColor,
        'paidAmountColor': paidAmountColor,
        'fontSettings': fontSettings.toJson(),
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        phoneNumbers: List<String>.from(json['phoneNumbers'] ?? []),
        remainingAmountColor: json['remainingAmountColor'] ?? Colors.black.value,
        discountColor: json['discountColor'] ?? Colors.black.value,
        loadingFeesColor: json['loadingFeesColor'] ?? Colors.black.value,
        totalBeforeDiscountColor: json['totalBeforeDiscountColor'] ?? Colors.black.value,
        totalAfterDiscountColor: json['totalAfterDiscountColor'] ?? Colors.black.value,
        previousDebtColor: json['previousDebtColor'] ?? Colors.black.value,
        currentDebtColor: json['currentDebtColor'] ?? Colors.black.value,
        electricPhoneColor: json['electricPhoneColor'] ?? Colors.black.value,
        healthPhoneColor: json['healthPhoneColor'] ?? Colors.black.value,
        companyDescriptionColor: json['companyDescriptionColor'] ?? Colors.black.value,
        companyDescription: json['companyDescription'] ?? 'لتجارة المواد الكهربائية والكيبلات و العدداليدوية والصحية',
        companyNameColor: json['companyNameColor'] ?? Colors.green.value,
        itemSerialColor: json['itemSerialColor'] ?? Colors.black.value,
        itemDetailsColor: json['itemDetailsColor'] ?? Colors.black.value,
        itemQuantityColor: json['itemQuantityColor'] ?? Colors.black.value,
        itemPriceColor: json['itemPriceColor'] ?? Colors.black.value,
        itemTotalColor: json['itemTotalColor'] ?? Colors.black.value,
        noticeColor: json['noticeColor'] ?? Colors.red.value,
        paidAmountColor: json['paidAmountColor'] ?? Colors.black.value,
        fontSettings: FontSettings.fromJson(json['fontSettings'] ?? {}),
      );

  AppSettings copyWith({
    List<String>? phoneNumbers,
    int? remainingAmountColor,
    int? discountColor,
    int? loadingFeesColor,
    int? totalBeforeDiscountColor,
    int? totalAfterDiscountColor,
    int? previousDebtColor,
    int? currentDebtColor,
    int? electricPhoneColor,
    int? healthPhoneColor,
    int? companyDescriptionColor,
    String? companyDescription,
    int? companyNameColor,
    int? itemSerialColor,
    int? itemDetailsColor,
    int? itemQuantityColor,
    int? itemPriceColor,
    int? itemTotalColor,
    int? noticeColor,
    int? paidAmountColor,
    FontSettings? fontSettings,
  }) {
    return AppSettings(
      phoneNumbers: phoneNumbers ?? this.phoneNumbers,
      remainingAmountColor: remainingAmountColor ?? this.remainingAmountColor,
      discountColor: discountColor ?? this.discountColor,
      loadingFeesColor: loadingFeesColor ?? this.loadingFeesColor,
      totalBeforeDiscountColor: totalBeforeDiscountColor ?? this.totalBeforeDiscountColor,
      totalAfterDiscountColor: totalAfterDiscountColor ?? this.totalAfterDiscountColor,
      previousDebtColor: previousDebtColor ?? this.previousDebtColor,
      currentDebtColor: currentDebtColor ?? this.currentDebtColor,
      electricPhoneColor: electricPhoneColor ?? this.electricPhoneColor,
      healthPhoneColor: healthPhoneColor ?? this.healthPhoneColor,
      companyDescriptionColor: companyDescriptionColor ?? this.companyDescriptionColor,
      companyDescription: companyDescription ?? this.companyDescription,
      companyNameColor: companyNameColor ?? this.companyNameColor,
      itemSerialColor: itemSerialColor ?? this.itemSerialColor,
      itemDetailsColor: itemDetailsColor ?? this.itemDetailsColor,
      itemQuantityColor: itemQuantityColor ?? this.itemQuantityColor,
      itemPriceColor: itemPriceColor ?? this.itemPriceColor,
      itemTotalColor: itemTotalColor ?? this.itemTotalColor,
      noticeColor: noticeColor ?? this.noticeColor,
      paidAmountColor: paidAmountColor ?? this.paidAmountColor,
      fontSettings: fontSettings ?? this.fontSettings,
    );
  }
}
