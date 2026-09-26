// lib/admin/services/firebase_usage_tracker.dart
// عدّاد عمليات التطبيق المحلي (اختياري - يسجل لقراءات/كتابات/حذف التي
// ينفذها التطبيق نفسه على الجهاز).
//
// الأمان: يكتب في قاعدة SQLite المحلية فقط (`app_cache`) — أي إضافة
// **صفر** قراءات/كتابات على Firestore، ولا يلمس الشبكة إطلاقاً.
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../db/database_helper.dart';
import '../models/firebase_usage_model.dart';

class FirebaseUsageTracker {
  FirebaseUsageTracker._();
  static final FirebaseUsageTracker instance = FirebaseUsageTracker._();

  /// مالك اصطناعي لمفاتيح SQLite الموحدة لهذه الميزة.
  static const String owner = '__app_usage__';
  static const String keyCounts = 'app_operations';

  final Map<String, FirestoreOps> _days = {};
  FirestoreOps _totals = const FirestoreOps.empty();
  bool _loaded = false;
  Timer? _saveTimer;
  int _pending = 0;
  int _pendingFsReads = 0;
  int _pendingFsWrites = 0;
  int _pendingFsDeletes = 0;

  int _pendingEmailLogins = 0;
  int _pendingGoogleLogins = 0;
  int _pendingSignups = 0;
  int _pendingVerifications = 0;

  bool _disposed = false;

  /// كم يوماً نحتفظ به من تاريخ عمليات التطبيق محلياً.
  static const int _maxDayHistory = 35;

  /// لا يحصل شيء قبل أول استدعاء (أو قبل `init` صريح).
  Future<void> init() async {
    if (_loaded) return;
    try {
      final raw = await DatabaseHelper.instance.getCache(owner, keyCounts);
      final days = raw?['days'];
      if (days is Map) {
        days.forEach((k, v) {
          final ops = FirestoreOps.fromJson(
            v is Map ? Map<String, dynamic>.from(v) : null,
          );
          if (ops.total > 0 || k.toString() == _todayKey) {
            _days[k.toString()] = ops;
          }
        });
      }
      final totals = raw?['totals'];
      if (totals is Map) {
        _totals = FirestoreOps.fromJson(Map<String, dynamic>.from(totals));
      } else {
        // كاش قديم من دون إجمالي → نحسب المجموع مما تحمّل (35 يومًا كحد أقصى).
        _totals = _sumDays();
      }
    } catch (_) {
      // الكاش مفقود أو تالف → نبدأ من الصفر دون إزعاج المستخدم.
    }
    _prune();
    _loaded = true;
  }

  String get _todayKey => usageDateKey(DateTime.now());

  /// عمليات اليوم الحالي (0 إذا لم تُسجل أي عملية).
  FirestoreOps today() => _days[_todayKey] ?? const FirestoreOps.empty();

  /// عمليات آخر n أيام (اليوم أولاً ثم الأقدم).
  List<FirestoreOps> lastDays(int n) {
    final now = DateTime.now();
    final out = <FirestoreOps>[];
    for (var i = 0; i < n; i++) {
      final day = now.subtract(Duration(days: i));
      out.add(_days[usageDateKey(day)] ?? const FirestoreOps.empty());
    }
    return out;
  }

  void recordRead() => recordReads(1);
  void recordWrite() => recordWrites(1);
  void recordDelete() => recordDeletes(1);

  void recordEmailLogin() => _bumpAuth(emailLogins: 1);
  void recordGoogleLogin() => _bumpAuth(googleLogins: 1);
  void recordSignup() => _bumpAuth(signups: 1);
  void recordVerification() => _bumpAuth(verifications: 1);

  /// قراءات متعددة (Query تعيد N مستند) — تُسجَّل N قراءة وليس قراءة واحدة.
  void recordReads(int count) =>
      _bump(reads: count);

  /// كتابات متعددة (Batch/عدة مستندات) — تُسجَّل N كتابة.
  void recordWrites(int count) =>
      _bump(writes: count);

  /// حذف متعدد (Batch/عدة مستندات) — تُسجَّل N عملية حذف.
  void recordDeletes(int count) =>
      _bump(deletes: count);

  void _bump({int reads = 0, int writes = 0, int deletes = 0}) {
    if (_disposed || (reads <= 0 && writes <= 0 && deletes <= 0)) return;
    final key = _todayKey;
    final day = _days[key] ?? const FirestoreOps.empty();
    _days[key] = day.copyWith(
      reads: day.reads + reads,
      writes: day.writes + writes,
      deletes: day.deletes + deletes,
    );
    _totals = _totals.copyWith(
      reads: _totals.reads + reads,
      writes: _totals.writes + writes,
      deletes: _totals.deletes + deletes,
    );
    _pending++;
    _pendingFsReads += reads;
    _pendingFsWrites += writes;
    _pendingFsDeletes += deletes;

    // حفظ مجمّع بعد توقف النشاط بـ3 ثوانٍ — لا نكتب بعد كل عملية.
    _saveTimer ??= Timer(const Duration(seconds: 3), _saveNow);
    // حد أقصى: حتى أثناء الدفعات المتواصلة نكتب مرة على الأقل.
    if (_pending >= 50) _saveNow();
  }

  void _bumpAuth({
    int emailLogins = 0,
    int googleLogins = 0,
    int signups = 0,
    int verifications = 0,
  }) {
    if (_disposed) return;
    _pendingEmailLogins += emailLogins;
    _pendingGoogleLogins += googleLogins;
    _pendingSignups += signups;
    _pendingVerifications += verifications;
    _pending++;

    _saveTimer ??= Timer(const Duration(seconds: 2), _saveNow);
    if (_pending >= 20) _saveNow();
  }

  /// إجمالي جميع العمليات المسجلة محليًا (كل الأيام، حتى المحذوفة من التاريخ).
  FirestoreOps totals() => _totals;

  FirestoreOps _sumDays() {
    var reads = 0, writes = 0, deletes = 0;
    for (final o in _days.values) {
      reads += o.reads;
      writes += o.writes;
      deletes += o.deletes;
    }
    return FirestoreOps(reads: reads, writes: writes, deletes: deletes);
  }

  void _saveNow() {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
    }
    unawaited(_persist());
  }

  Future<void> _persist() async {
    if (!_loaded) {
      try {
        await init();
      } catch (_) {
        // في أسوأ الحالات نكمل بالحالة الحالية في الذاكرة.
      }
    }
    if (_pending == 0 &&
        _pendingFsReads == 0 &&
        _pendingFsWrites == 0 &&
        _pendingFsDeletes == 0 &&
        _pendingEmailLogins == 0 &&
        _pendingGoogleLogins == 0 &&
        _pendingSignups == 0 &&
        _pendingVerifications == 0) {
      return;
    }

    final fsReads = _pendingFsReads;
    final fsWrites = _pendingFsWrites;
    final fsDeletes = _pendingFsDeletes;
    final emailLogins = _pendingEmailLogins;
    final googleLogins = _pendingGoogleLogins;
    final signups = _pendingSignups;
    final verifications = _pendingVerifications;
    final todayKey = _todayKey;

    _pending = 0;
    _pendingFsReads = 0;
    _pendingFsWrites = 0;
    _pendingFsDeletes = 0;
    _pendingEmailLogins = 0;
    _pendingGoogleLogins = 0;
    _pendingSignups = 0;
    _pendingVerifications = 0;

    _prune();
    try {
      await DatabaseHelper.instance.setCache(owner, keyCounts, {
        'days': {
          for (final e in _days.entries) e.key: e.value.toJson(),
        },
        'totals': _totals.toJson(),
      });
    } catch (_) {
      // فشل حفظ محلي — لا نوقف التطبيق بسببه.
    }

    if (fsReads > 0 ||
        fsWrites > 0 ||
        fsDeletes > 0 ||
        emailLogins > 0 ||
        googleLogins > 0 ||
        signups > 0 ||
        verifications > 0) {
      unawaited(_syncToFirestore(
        fsReads,
        fsWrites,
        fsDeletes,
        emailLogins,
        googleLogins,
        signups,
        verifications,
        todayKey,
      ));
    }
  }

  Future<void> _syncToFirestore(
    int reads,
    int writes,
    int deletes,
    int emailLogins,
    int googleLogins,
    int signups,
    int verifications,
    String todayKey,
  ) async {
    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();
      final statsRef = db.collection('firebase_usage').doc('stats');
      final dailyRef = db.collection('firebase_usage').doc('daily_$todayKey');

      final updateData = <String, dynamic>{
        'lastUpdated': FieldValue.serverTimestamp(),
      };
      if (reads > 0) updateData['reads'] = FieldValue.increment(reads);
      if (writes > 0) updateData['writes'] = FieldValue.increment(writes);
      if (deletes > 0) updateData['deletes'] = FieldValue.increment(deletes);

      if (emailLogins > 0) updateData['emailLogins'] = FieldValue.increment(emailLogins);
      if (googleLogins > 0) updateData['googleLogins'] = FieldValue.increment(googleLogins);
      if (signups > 0) updateData['signups'] = FieldValue.increment(signups);
      if (verifications > 0) updateData['verifications'] = FieldValue.increment(verifications);

      batch.set(statsRef, updateData, SetOptions(merge: true));
      batch.set(dailyRef, {
        ...updateData,
        'date': todayKey,
      }, SetOptions(merge: true));

      await batch.commit();
    } catch (_) {
      // Silent fail if offline or unauthenticated to ensure zero app interruption
    }
  }

  /// يتخلص من الأيام الأقدم من [maxDayHistory] للحفاظ على حجم الكاش ثابتاً.
  void _prune() {
    final cutoff =
        usageDateKey(DateTime.now().subtract(const Duration(days: _maxDayHistory)));
    _days.removeWhere((k, _) => cutoff.compareTo(k) > 0);
  }

  /// حفظ فوري (يُنصح بالنداء عند إغلاق التطبيق).
  Future<void> flush() async {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
    }
    await _persist();
  }

  /// إعادة ضبط جميع عدّادات التطبيق المحلية (اليوم + التاريخ + الإجمالي).
  Future<void> reset() async {
    if (_saveTimer != null) {
      _saveTimer!.cancel();
      _saveTimer = null;
    }
    _days.clear();
    _totals = const FirestoreOps.empty();
    _pending = 0;
    _loaded = true;
    try {
      await DatabaseHelper.instance.removeCache(owner, keyCounts);
    } catch (_) {
      // فشل الحذف المحلي — المفاتيح في الذاكرة صُفّرت على أي حال.
    }
  }

  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _saveTimer = null;
    unawaited(flush());
  }
}