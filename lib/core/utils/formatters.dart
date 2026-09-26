// lib/core/utils/formatters.dart
// أدوات تنسيق موحّدة للتاريخ والأرقام.
//
// يستخدم التطبيق حالياً النمط `'${value.toStringAsFixed(2)} ريال'`
// في عدة شاشات؛ هذه الدوال تركزه في مكان واحد مع الحفاظ على نفس المخرجات.

class Formatters {
  Formatters._();

  /// نفس المخرجات الحالية: `1234.5` → `'1234.50 ريال'`.
  static String money(num value, {int decimals = 2}) =>
      '${value.toStringAsFixed(decimals)} ريال';

  /// رقم بلا عملة (يُحافظ على نفس toStringAsFixed الحالي).
  static String number(num value, {int decimals = 0}) =>
      value.toStringAsFixed(decimals);

  /// تحليل تاريخ بأسلوب آمن: يُعيد التاريخ أو null دون رمي استثناء.
  /// (يحل محل أنماط try/catch المكررة في كشوف الحساب والتقارير).
  static DateTime? tryParseDate(String? value) =>
      value == null ? null : DateTime.tryParse(value);
}