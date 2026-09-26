// lib/admin/models/firebase_usage_quota.dart
// الحصص المجانية الحالية لخطة Spark وقاعدة حساب مستوى التحذير.
//
// ⚠️ هذه القيم تُعدَّل من هذا المكان الوحيد فقط.
// المصدر الرسمي (يُحدَّث دورياً): https://firebase.google.com/docs/firestore/quotas
import 'package:flutter/foundation.dart';

/// الحدود المجانية الحالية لدى Google (عبّر عنها بروح الموقع الرسمي):
/// - قراءات: 50,000 / يوم
/// - كتابات: 20,000 / يوم
/// - حذف: 20,000 / يوم
/// - تخزين: 1 GiB
/// - ناتج الإنترنت: 10 GiB / شهر
///
/// ملاحظة: التخزين والإنترنت خارج البيانات الرسمية القياسية (Monitoring
/// لا يوفرها لـ Native mode) — تُحسب هنا للمرجعية في التقرير فقط.
@immutable
class QuotaLimits {
  final int readsPerDay;
  final int writesPerDay;
  final int deletesPerDay;
  final int? storageBytes;
  final int outboundBytesPerMonth;

  const QuotaLimits({
    required this.readsPerDay,
    required this.writesPerDay,
    required this.deletesPerDay,
    required this.storageBytes,
    required this.outboundBytesPerMonth,
  });

  /// قيم Spark الحالية (أفضلها للمرجعية).
  static const QuotaLimits spark = QuotaLimits(
    readsPerDay: 50000,
    writesPerDay: 20000,
    deletesPerDay: 20000,
    storageBytes: 1073741824, // 1 GiB
    outboundBytesPerMonth: 10737418240, // 10 GiB
  );
}

/// مستويات التحذير بالنسبة المئوية من الحصة.
enum UsageAlertLevel { normal, warning, danger, critical }

/// نتيجة مقارنة الاستهلاك بالحصة الواحدة (تُعرض في البطاقات).
@immutable
class QuotaStatus {
  final int used;
  final int limit;
  final double ratio;
  final int remaining;

  const QuotaStatus({
    required this.used,
    required this.limit,
    required this.ratio,
    required this.remaining,
  });

  factory QuotaStatus.of(int used, int limit) {
    final ratio = limit <= 0 ? 0.0 : used / limit;
    return QuotaStatus(
      used: used,
      limit: limit,
      ratio: ratio,
      remaining: limit - used,
    );
  }

  /// النسبة السالبة تعني تجاوز الحصة.
  bool get overQuota => remaining < 0;

  UsageAlertLevel get level {
    if (ratio >= 1) return UsageAlertLevel.critical;
    if (ratio >= 0.9) return UsageAlertLevel.danger;
    if (ratio >= 0.8) return UsageAlertLevel.warning;
    return UsageAlertLevel.normal;
  }
}

/// تنبيه جاهز للعرض عند اقتراب/تجاوز إحدى الحصص (90% فأكثر).
@immutable
class QuotaAlert {
  final String label;
  final QuotaStatus status;

  const QuotaAlert({required this.label, required this.status});

  bool get isCritical => status.level == UsageAlertLevel.critical;
  bool get isOver => status.overQuota;

  String get ratioText => '${(status.ratio * 100).toStringAsFixed(1)}%';

  String get summary => isOver
      ? '$label: تم تجاوز الحصة — الاستهلاك $ratioText من الحد (زيادة '
          '${status.remaining.abs()}).'
      : '$label: استهلكت $ratioText من الحصة — المتبقي ${status.remaining}.';
}