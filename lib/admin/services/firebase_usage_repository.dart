// lib/admin/services/firebase_usage_repository.dart
// طبقة التنسيق بين:
//   AdminApi (Backend الرسمي)  ←  SQLite (كاش)  ←  FirebaseUsageTracker (عمليات التطبيق)
// القاعدة: لا نخترع أرقاماً أبداً — إن تعذّرت البيانات الرسمية نعرض آخر
// كاش ناجح مع إخبار واضح، وإن لم يوجد كاش نعرض "غير متاحة" مع السبب.
import '../../db/database_helper.dart';
import '../models/firebase_usage_model.dart';
import 'admin_api.dart';
import 'admin_firestore_service.dart';
import 'firebase_usage_tracker.dart';

class FirebaseUsageRepository {
  FirebaseUsageRepository._();
  static final FirebaseUsageRepository instance = FirebaseUsageRepository._();

  static const String _owner = FirebaseUsageTracker.owner;
  static const String _keyOfficial = 'official_usage';

  Future<void> init() => FirebaseUsageTracker.instance.init();

  /// يحمّل لقطة الاستخدام الحالية.
  ///
  /// [days] عدد الأيام في السلسلة الرسمية (1-30، افتراضياً 7).
  /// [forceRefresh] يتجاوز الكاش الحديث ويطلب الشبكة (إعادة المزامنة اليدوية).
  Future<UsageSnapshot> load({
    int days = 7,
    bool forceRefresh = false,
  }) async {
    // نضمن تحميل سجل عمليات التطبيق المحلي قبل كل قراءة.
    await FirebaseUsageTracker.instance.init();

    final officialRaw =
        await DatabaseHelper.instance.getCache(_owner, _keyOfficial);
    final cached = officialRaw != null
        ? OfficialFirebaseUsage.fromJson(officialRaw)
        : null;

    OfficialFirebaseUsage? display;
    var fromCache = false;
    String? error;

    if (!forceRefresh &&
        cached != null &&
        !_isStale(cached.fetchedAt) &&
        cached.usageAvailable) {
      display = cached;
      fromCache = true;
    } else {
      try {
        final raw = await AdminApi.instance.getFirebaseUsage(days: days);
        final official = OfficialFirebaseUsage.fromJson(raw);
        if (official.usageAvailable) {
          display = official;
          fromCache = false;
          error = null;
          await DatabaseHelper.instance
              .setCache(_owner, _keyOfficial, official.toJson());
        } else {
          // الخادم حي لكنه رفض (API غير مفعّل / صلاحيات Monitoring) →
          // عرّف السبب، واعرض الكاش القديم إن وُجد.
          error = official.errorMessage ?? 'البيانات الرسمية غير متاحة حالياً';
          if (official.errorCode != null) {
            error = '${official.errorCode}: $error';
          }
          display = cached?.usageAvailable == true ? cached : null;
          fromCache = display != null;
        }
      } catch (e) {
        error = e.toString();
        display = cached?.usageAvailable == true ? cached : null;
        fromCache = display != null;
      }
    }

    // قراءة إحصائيات Firestore المباشرة (جدول firebase_usage في قاعدة البيانات)
    FirestoreDbUsage? dbUsage;
    try {
      dbUsage = await AdminFirestoreService.instance.fetchFirestoreDbUsage(days: days);
    } catch (_) {
      dbUsage = null;
    }

    // عدّادات التطبيق تُقرأ على أي حال (محلية وفورية).
    final appOps = FirebaseUsageTracker.instance.today();
    final appHistory = FirebaseUsageTracker.instance.lastDays(7);

    return UsageSnapshot(
      official: display,
      dbUsage: dbUsage,
      officialFromCache: fromCache,
      officialError: error,
      officialCachedAt: display?.fetchedAt ?? cached?.fetchedAt,
      appOps: appOps,
      appHistory: appHistory,
      loadedAt: DateTime.now(),
    );
  }

  /// مسح كاش البيانات الرسمية المحلي (تجاوز عند التحقيق/التصحيح).
  Future<void> clearOfficialCache() async {
    await DatabaseHelper.instance.removeCache(_owner, _keyOfficial);
  }

  bool _isStale(DateTime fetchedAt) {
    return DateTime.now().toUtc().difference(fetchedAt.toUtc()) >
        UsageSnapshot.staleAfter;
  }
}