// lib/admin/controllers/firebase_usage_controller.dart
import 'package:flutter/foundation.dart';

import '../models/firebase_usage_model.dart';
import '../models/firebase_usage_quota.dart';
import '../services/firebase_usage_repository.dart';
import '../services/firebase_usage_tracker.dart';

class FirebaseUsageController extends ChangeNotifier {
  UsageSnapshot? snapshot;
  bool isLoading = true;
  bool isRefreshing = false;
  String? error;

  /// نطاق الأيام في السلسلة الزمنية الرسمية (7 / 14 / 30).
  int days = 7;

  static const Duration _rateLimit = Duration(minutes: 1);

  DateTime? _lastManualRefreshAt;
  bool _sessionExpiredNotified = false;
  bool _disposed = false;

  /// يُستدعى عند فقدان صلاحية الأدمن أثناء الجلسة (permission-denied).
  void Function()? onSessionExpired;

  /// حد أدنى دقيقة واحدة بين التحديثات اليدوية (Rate limiting في الواجهة).
  bool get canRefresh {
    final last = _lastManualRefreshAt;
    if (last == null) return true;
    return DateTime.now().difference(last) >= _rateLimit;
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await FirebaseUsageTracker.instance.flush();
      snapshot = await FirebaseUsageRepository.instance.load(days: days);
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  /// تحديث يدوي: يجبر الشبكة (بدون كاش حديث) ويعيد تسمية وقت آخر تحديث.
  Future<void> refresh() async {
    isRefreshing = true;
    notifyListeners();
    try {
      await FirebaseUsageTracker.instance.flush();
      snapshot =
          await FirebaseUsageRepository.instance.load(days: days, forceRefresh: true);
      _lastManualRefreshAt = DateTime.now();
    } catch (e) {
      error = e.toString();
      _onSessionError(e);
    }
    isRefreshing = false;
    notifyListeners();
  }

  void setDays(int value) {
    if (value == days) return;
    days = value;
    load();
  }

  /// تحديث خلفي هادئ: يُستدعى دورياً من الشاشة. لا يُظهر مؤشر التحميل الكامل
  /// حتى لا يرمش عند الاعتماد على كاش سليم — Repository يقرر بنفسه
  /// إن كان الكاش حديثاً فيعرضه دون شبكة، أو منتهياً فيجلب من الخادم.
  Future<void> loadIfNeeded() async {
    if (isLoading || isRefreshing) return;
    try {
      final next =
          await FirebaseUsageRepository.instance.load(days: days);
      snapshot = next;
      error = null;
      notifyListeners();
    } catch (e) {
      error = e.toString();
      _onSessionError(e);
      notifyListeners();
    }
  }

  // ========== حسابات جاهزة للبطاقات ==========
  bool get hasOfficialData => snapshot?.hasOfficialData ?? false;
  String? get officialError => snapshot?.officialError;
  bool get officialFromCache => snapshot?.officialFromCache ?? false;
  bool get isOfficialStale => snapshot?.isOfficialStale ?? true;

  // إحصائيات قاعدة البيانات المباشرة Firestore
  bool get hasDbUsage => snapshot?.hasDbUsage ?? false;
  FirestoreDbUsage? get dbUsage => snapshot?.dbUsage;
  FirestoreOps get dbToday {
    final ops = snapshot?.dbUsage?.today;
    if (ops != null && !ops.isZero) return ops;
    return snapshot?.appOps ?? const FirestoreOps.empty();
  }

  FirestoreOps get dbTotals {
    final ops = snapshot?.dbUsage?.totals;
    if (ops != null && !ops.isZero) return ops;
    return FirebaseUsageTracker.instance.totals();
  }

  AuthEventsOps get dbAuthToday =>
      snapshot?.dbUsage?.todayAuth ?? const AuthEventsOps.empty();

  AuthEventsOps get dbAuthTotals =>
      snapshot?.dbUsage?.totalsAuth ?? const AuthEventsOps.empty();

  String get dbStorageSizeFormatted {
    final bytes = snapshot?.dbUsage?.storageBytes ?? snapshot?.official?.storageBytes;
    return formatBytes(bytes);
  }

  List<FirestoreDailyPoint> get dbDaily => snapshot?.dbUsage?.daily ?? const [];

  QuotaStatus get dbReadsStatus =>
      QuotaStatus.of(dbToday.reads, QuotaLimits.spark.readsPerDay);

  QuotaStatus get dbWritesStatus =>
      QuotaStatus.of(dbToday.writes, QuotaLimits.spark.writesPerDay);

  QuotaStatus get dbDeletesStatus =>
      QuotaStatus.of(dbToday.deletes, QuotaLimits.spark.deletesPerDay);

  FirestoreOps? get todayOfficial => snapshot?.official?.today;
  FirestoreOps? get monthOfficial => snapshot?.official?.month;
  int? get authUsers => snapshot?.official?.authUsers;

  QuotaStatus? get readsStatus {
    final t = todayOfficial;
    if (t == null) return dbReadsStatus;
    return QuotaStatus.of(t.reads, QuotaLimits.spark.readsPerDay);
  }

  QuotaStatus? get writesStatus {
    final t = todayOfficial;
    if (t == null) return dbWritesStatus;
    return QuotaStatus.of(t.writes, QuotaLimits.spark.writesPerDay);
  }

  QuotaStatus? get deletesStatus {
    final t = todayOfficial;
    if (t == null) return dbDeletesStatus;
    return QuotaStatus.of(t.deletes, QuotaLimits.spark.deletesPerDay);
  }

  /// تنبيهات نشطة (90% فأكثر من الحصة) لعرضها في شريط أعلى القسم الرسمي.
  List<QuotaAlert> get activeAlerts {
    final out = <QuotaAlert>[];
    void add(String label, QuotaStatus? st) {
      if (st == null) return;
      if (st.level == UsageAlertLevel.danger ||
          st.level == UsageAlertLevel.critical) {
        out.add(QuotaAlert(label: label, status: st));
      }
    }

    add('قراءات اليوم', readsStatus);
    add('كتابات اليوم', writesStatus);
    add('حذف اليوم', deletesStatus);
    return out;
  }

  bool get hasActiveAlerts => activeAlerts.isNotEmpty;

  void _onSessionError(Object e) {
    final s = e.toString();
    if ((s.contains('permission-denied') ||
            s.contains('PERMISSION_DENIED') ||
            s.contains('unauthenticated')) &&
        !_sessionExpiredNotified) {
      _sessionExpiredNotified = true;
      onSessionExpired?.call();
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}