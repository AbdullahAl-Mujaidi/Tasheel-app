// lib/admin/models/firebase_usage_model.dart
// نماذج بيانات الاستخدام:
// 1) البيانات الرسمية القياسية من Google Cloud Monitoring (عبر Cloud Function).
// 2) عدّاد عمليات التطبيق المحلي (اختياري - بدون أي استهلاك Firestore إضافي).
import 'package:flutter/foundation.dart';

/// عمليات Firestore (قراءات/كتابات/حذف).
/// تُستخدم لليوم الحالي والشهر والنقاط اليومية (رسمية + عمليات التطبيق).
@immutable
class FirestoreOps {
  final int reads;
  final int writes;
  final int deletes;

  const FirestoreOps({
    required this.reads,
    required this.writes,
    required this.deletes,
  });

  const FirestoreOps.empty()
      : reads = 0,
        writes = 0,
        deletes = 0;

  int get total => reads + writes + deletes;

  bool get isZero => reads == 0 && writes == 0 && deletes == 0;

  FirestoreOps copyWith({int? reads, int? writes, int? deletes}) =>
      FirestoreOps(
        reads: reads ?? this.reads,
        writes: writes ?? this.writes,
        deletes: deletes ?? this.deletes,
      );

  factory FirestoreOps.fromJson(Map<String, dynamic>? json) => FirestoreOps(
        reads: (json?['reads'] as num?)?.toInt() ?? 0,
        writes: (json?['writes'] as num?)?.toInt() ?? 0,
        deletes: (json?['deletes'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'reads': reads, 'writes': writes, 'deletes': deletes};
}

/// مفتاح تاريخ (yyyy-MM-dd) بالمنطقة الزمنية المعطاة — يُستخدم للمفاتيح المحلية
/// وللنقاط الرسمية (UTC وفق توقيت Google).
String usageDateKey(DateTime d, {bool utc = false}) {
  final t = utc ? d.toUtc() : d;
  final y = t.year.toString().padLeft(4, '0');
  final m = t.month.toString().padLeft(2, '0');
  final day = t.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

/// نقطة يومية في السلسلة الزمنية (الرسمية تأتي من Monitoring بتوقيت UTC).
@immutable
class FirestoreDailyPoint {
  final DateTime date;
  final FirestoreOps ops;

  const FirestoreDailyPoint({required this.date, required this.ops});

  factory FirestoreDailyPoint.fromJson(Map<String, dynamic> json) {
    final dateStr = json['date']?.toString();
    DateTime date;
    final parts = dateStr?.split('-');
    if (parts != null && parts.length == 3) {
      date = DateTime.utc(
        int.tryParse(parts[0]) ?? 0,
        int.tryParse(parts[1]) ?? 1,
        int.tryParse(parts[2]) ?? 1,
      );
    } else {
      date = DateTime.utc(2020, 1, 1);
    }
    return FirestoreDailyPoint(
      date: date,
      ops: FirestoreOps.fromJson(json),
    );
  }

  Map<String, dynamic> toJson() => {
        'date': usageDateKey(date, utc: true),
        ...ops.toJson(),
      };
}

/// الاستجابة الرسمية من Cloud Function `getFirebaseUsage`.
///
/// عند `usageAvailable == false` تكون `errorCode`/`errorMessage` فاعلة
/// (مثل `api_not_enabled` أو `permission_denied`) وnull باقي الحقول.
@immutable
class OfficialFirebaseUsage {
  final bool usageAvailable;
  final DateTime fetchedAt;
  final int? authUsers;
  final FirestoreOps? today;
  final FirestoreOps? month;
  final List<FirestoreDailyPoint> daily;

  /// التخزين غير متاح رسمياً عبر Monitoring لـ Native mode → المتوقع false.
  final bool storageAvailable;
  final double? storageBytes;

  final String? errorCode;
  final String? errorMessage;

  const OfficialFirebaseUsage({
    required this.usageAvailable,
    required this.fetchedAt,
    this.authUsers,
    this.today,
    this.month,
    this.daily = const [],
    this.storageAvailable = false,
    this.storageBytes,
    this.errorCode,
    this.errorMessage,
  });

  factory OfficialFirebaseUsage.fromJson(Map<String, dynamic> json) {
    final dailyRaw = json['daily'];
    final List<FirestoreDailyPoint> daily = dailyRaw is List
        ? dailyRaw
            .map<FirestoreDailyPoint>((e) => FirestoreDailyPoint.fromJson(
                Map<String, dynamic>.from((e as Map?) ?? {})))
            .toList()
        : const [];
    final today = json['today'];
    final month = json['month'];
    return OfficialFirebaseUsage(
      usageAvailable: json['usageAvailable'] == true,
      fetchedAt: DateTime.tryParse(json['fetchedAt']?.toString() ?? '') ??
          DateTime.now(),
      authUsers: (json['authUsers'] as num?)?.toInt(),
      today: today is Map ? FirestoreOps.fromJson(Map<String, dynamic>.from(today)) : null,
      month: month is Map ? FirestoreOps.fromJson(Map<String, dynamic>.from(month)) : null,
      daily: daily,
      storageAvailable: json['storageAvailable'] == true,
      storageBytes: (json['storageBytes'] as num?)?.toDouble(),
      errorCode: json['errorCode']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'usageAvailable': usageAvailable,
        'fetchedAt': fetchedAt.toUtc().toIso8601String(),
        'authUsers': authUsers,
        'today': today?.toJson(),
        'month': month?.toJson(),
        'daily': daily.map((e) => e.toJson()).toList(),
        'storageAvailable': storageAvailable,
        'storageBytes': storageBytes,
        'errorCode': errorCode,
        'errorMessage': errorMessage,
      };
}

/// إحصائيات أحداث الحسابات وتسجيل الدخول (عادي/جوجل/إنشاء/توثيق).
@immutable
class AuthEventsOps {
  final int emailLogins;
  final int googleLogins;
  final int signups;
  final int verifications;

  const AuthEventsOps({
    required this.emailLogins,
    required this.googleLogins,
    required this.signups,
    required this.verifications,
  });

  const AuthEventsOps.empty()
      : emailLogins = 0,
        googleLogins = 0,
        signups = 0,
        verifications = 0;

  int get totalLogins => emailLogins + googleLogins;

  bool get isZero =>
      emailLogins == 0 &&
      googleLogins == 0 &&
      signups == 0 &&
      verifications == 0;

  AuthEventsOps copyWith({
    int? emailLogins,
    int? googleLogins,
    int? signups,
    int? verifications,
  }) =>
      AuthEventsOps(
        emailLogins: emailLogins ?? this.emailLogins,
        googleLogins: googleLogins ?? this.googleLogins,
        signups: signups ?? this.signups,
        verifications: verifications ?? this.verifications,
      );

  factory AuthEventsOps.fromJson(Map<String, dynamic>? json) => AuthEventsOps(
        emailLogins: (json?['emailLogins'] as num?)?.toInt() ?? 0,
        googleLogins: (json?['googleLogins'] as num?)?.toInt() ?? 0,
        signups: (json?['signups'] as num?)?.toInt() ?? 0,
        verifications: (json?['verifications'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'emailLogins': emailLogins,
        'googleLogins': googleLogins,
        'signups': signups,
        'verifications': verifications,
      };
}

/// تنسيق الحجم البايتي بشكل واضح (B/KB/MB/GB).
String formatBytes(double? bytes) {
  if (bytes == null || bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  var d = bytes;
  while (d >= 1024 && i < suffixes.length - 1) {
    d /= 1024;
    i++;
  }
  return '${d.toStringAsFixed(d < 10 && i > 0 ? 2 : 1)} ${suffixes[i]}';
}

/// إحصائيات الاستهلاك المسجلة في جدول Firestore المباشر (قاعدة البيانات).
@immutable
class FirestoreDbUsage {
  final FirestoreOps totals;
  final FirestoreOps today;
  final AuthEventsOps totalsAuth;
  final AuthEventsOps todayAuth;
  final double? storageBytes;
  final List<FirestoreDailyPoint> daily;
  final DateTime fetchedAt;

  const FirestoreDbUsage({
    required this.totals,
    required this.today,
    required this.totalsAuth,
    required this.todayAuth,
    this.storageBytes,
    required this.daily,
    required this.fetchedAt,
  });

  factory FirestoreDbUsage.empty() => FirestoreDbUsage(
        totals: const FirestoreOps.empty(),
        today: const FirestoreOps.empty(),
        totalsAuth: const AuthEventsOps.empty(),
        todayAuth: const AuthEventsOps.empty(),
        storageBytes: null,
        daily: const [],
        fetchedAt: DateTime.now(),
      );

  bool get isEmpty =>
      totals.isZero && today.isZero && totalsAuth.isZero && daily.isEmpty;
}

/// لقطة مجمّعة يستهلكها المتحكم (Controller) في لوحة المدير:
/// البيانات الرسمية + بيانات Firestore المباشرة + عدّاد عمليات التطبيق + حالة الكاش/الخطأ.
@immutable
class UsageSnapshot {
  /// آخر بيانات رسمية متاحة (طازجة أو من الكاش أو null تماماً).
  final OfficialFirebaseUsage? official;

  /// إحصائيات قاعدة البيانات المباشرة المسجلة في جدول Firestore.
  final FirestoreDbUsage? dbUsage;

  /// true عند العرض من الكاش المحلي وليس من الشبكة.
  final bool officialFromCache;

  /// نص خطأ آخر محاولة اتصال بالبيانات الرسمية (للعرض عند عدم التوفر).
  final String? officialError;

  /// آخر وقت نجح فيه التطبيق في الحصول على بيانات رسمية (حتى العرض من كاش).
  final DateTime? officialCachedAt;

  /// عدّاد عمليات التطبيق المحلي لليوم الحالي.
  final FirestoreOps appOps;

  /// تاريخ آخر 7 أيام لعمليات التطبيق (أحدث يوم أولاً).
  final List<FirestoreOps> appHistory;

  final DateTime loadedAt;

  const UsageSnapshot({
    required this.official,
    this.dbUsage,
    required this.officialFromCache,
    required this.officialError,
    required this.officialCachedAt,
    required this.appOps,
    required this.appHistory,
    required this.loadedAt,
  });

  static const Duration staleAfter = Duration(minutes: 15);

  /// هل البيانات الرسمية المعروضة قديمة (> 15 دقيقة) من غير تحديث ناجح؟
  bool get isOfficialStale {
    final t = official?.fetchedAt ?? officialCachedAt;
    if (t == null) return true;
    return DateTime.now().toUtc().difference(t.toUtc()) > staleAfter;
  }

  bool get hasOfficialData => official?.usageAvailable == true;
  bool get hasAnyOfficialCached => official != null || officialCachedAt != null;
  bool get hasDbUsage => dbUsage != null && !dbUsage!.isEmpty;
}