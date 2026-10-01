// lib/admin/services/admin_firestore_service.dart
// قراءة/كتابة بيانات لوحة المدير عبر Firestore (تخضع لقواعد Firestore).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/admin_models.dart';
import '../models/firebase_usage_model.dart';

class AdminFirestoreService {
  AdminFirestoreService._();
  static final AdminFirestoreService instance = AdminFirestoreService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ===================== المستخدمون =====================
  Future<({List<UserSnapshot> users, DocumentSnapshot? last})> fetchUsers({
    int limit = 50,
    DocumentSnapshot? startAfter,
  }) async {
    // استعلام Firestore المُرتب بـ createdAt يحذف صمتاً أي وثيقة تفتقد الحقل
    // (مثل حسابات الفريق التي أُنشئت دون createdAt)، لذا نجلب الكل ونرتب في
    // الذاكرة ونُرَقِّم يدوياً — أي وثيقة بلا createdAt تُعامل كالأقدم.
    final snap = await _db.collection('users').get();
    final all = snap.docs.toList();

    int sortKey(QueryDocumentSnapshot<Map<String, dynamic>> d) {
      final ts = d.data()['createdAt'];
      if (ts is Timestamp) return ts.millisecondsSinceEpoch;
      if (ts is DateTime) return ts.millisecondsSinceEpoch;
      return 0;
    }

    all.sort((a, b) => sortKey(b).compareTo(sortKey(a)));

    int startIdx = 0;
    if (startAfter != null) {
      final i = all.indexWhere((d) => d.id == startAfter.id);
      startIdx = i < 0 ? all.length : i + 1;
    }
    final endIdx = (startIdx + limit) > all.length ? all.length : startIdx + limit;
    final page = all.sublist(startIdx, endIdx);
    return (
      users: page.map(UserSnapshot.fromDoc).toList(),
      last: page.isEmpty ? null : page.last,
    );
  }

  /// قراءة آخر المستخدمين نشاطاً (مخصص لغرض "حالة المزامنة"):
  /// يُرتَّب تنازلياً حسب `lastActivityAt` بحد أقصى 200 سجل.
  Future<({List<UserSnapshot> users, DocumentSnapshot? last})> fetchLatestByActivity({
    int limit = 200,
  }) async {
    final snap = await _db
        .collection('users')
        .orderBy('lastActivityAt', descending: true)
        .limit(limit)
        .get();
    return (
      users: snap.docs.map(UserSnapshot.fromDoc).toList(),
      last: snap.docs.isEmpty ? null : snap.docs.last,
    );
  }

  Future<List<UserCounts>> fetchUserCounts(List<String> uids) async {
    if (uids.isEmpty) return [];

    final result = <UserCounts>[];
    final mapByUid = <String, UserCounts>{};

    // 1. محاولة القراءة أولاً من وثائق admin_stats الجاهزة إن وجدت
    final ids = uids.map((u) => 'user_counts/$u').toList();
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, (i + 30) > ids.length ? ids.length : i + 30);
      try {
        final snap = await _db
            .collection('admin_stats')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          final counts = UserCounts.fromDoc(doc);
          if (counts.businessCount > 0) {
            mapByUid[counts.uid] = counts;
          }
        }
      } catch (_) {}
    }

    // 2. للمستخدمين الذين لم توجد لهم إحصائيات جاهزة أو كانت 0، استعلام مباشر من users/{uid}/businesses
    for (final uid in uids) {
      if (mapByUid.containsKey(uid)) {
        result.add(mapByUid[uid]!);
        continue;
      }

      try {
        final bizSnap = await _db
            .collection('users')
            .doc(uid)
            .collection('businesses')
            .get();

        final bCount = bizSnap.docs.length;
        int cCount = 0;
        int pCount = 0;
        for (final doc in bizSnap.docs) {
          final st = doc.data()['status']?.toString();
          if (st == 'completed' || st == 'مكتمل') {
            cCount++;
          } else {
            pCount++;
          }
        }
        result.add(UserCounts(
          uid: uid,
          businessCount: bCount,
          completedCount: cCount,
          inProgressCount: pCount,
        ));
      } catch (_) {
        result.add(UserCounts.empty(uid));
      }
    }

    return result;
  }

  Future<List<UserSnapshot>> searchUsers(String query, {int limit = 100}) async {
    final q = query.trim().toLowerCase();
    final all = (await fetchUsers(limit: limit)).users;
    if (q.isEmpty) return all;
    return all.where((u) {
      return u.email.toLowerCase().contains(q) ||
          u.fullName.toLowerCase().contains(q) ||
          u.uid.toLowerCase().contains(q);
    }).toList();
  }

  // ===================== الإحصائيات =====================
  Future<DashboardStats?> fetchDashboardStats() async {
    try {
      final doc = await _db.collection('admin_stats').doc('dashboard').get();
      if (doc.exists) {
        final stats = DashboardStats.fromDoc(doc);
        if (stats.totalUsers > 0 && stats.totalBusinesses > 0) return stats;
      }
    } catch (_) {}

    // حساب احتياطي مجاني ومباشر من قاعدة البيانات (Spark Plan Fallback)
    try {
      final usersSnap = await _db.collection('users').get();
      final users = usersSnap.docs.map(UserSnapshot.fromDoc).toList();
      final now = DateTime.now();
      final d7 = now.subtract(const Duration(days: 7));
      final d30 = now.subtract(const Duration(days: 30));

      int new7 = 0;
      int new30 = 0;
      int active7 = 0;
      int active30 = 0;
      final versionDist = <String, int>{};

      for (final u in users) {
        if (u.createdAt != null) {
          if (u.createdAt!.isAfter(d7)) new7++;
          if (u.createdAt!.isAfter(d30)) new30++;
        }
        final lastAct = u.lastActivityAt ?? u.lastLoginAt ?? u.createdAt;
        if (lastAct != null) {
          if (lastAct.isAfter(d7)) active7++;
          if (lastAct.isAfter(d30)) active30++;
        }
        if (u.appVersion.isNotEmpty && u.appVersion != '-') {
          versionDist[u.appVersion] = (versionDist[u.appVersion] ?? 0) + 1;
        }
      }

      int totalBiz = 0;
      int completedBiz = 0;
      int inProgBiz = 0;
      int totalWorkers = 0;

      // محاولة أولية عبر collectionGroup
      try {
        final bizSnap = await _db.collectionGroup('businesses').get();
        totalBiz = bizSnap.docs.length;
        for (final doc in bizSnap.docs) {
          final st = doc.data()['status']?.toString();
          if (st == 'completed' || st == 'مكتمل') {
            completedBiz++;
          } else {
            inProgBiz++;
          }
        }
      } catch (_) {}

      try {
        final workerSnap = await _db.collectionGroup('workers').get();
        totalWorkers = workerSnap.docs.length;
      } catch (_) {}

      // احتياطي إضافي عند إرجاع collectionGroup للصفر: المرور المباشر على مجموعات المستخدمين
      if (totalBiz == 0 || totalWorkers == 0) {
        int iterBiz = 0;
        int iterCompleted = 0;
        int iterInProgress = 0;
        int iterWorkers = 0;

        for (final u in users) {
          try {
            final bSnap = await _db.collection('users').doc(u.uid).collection('businesses').get();
            if (bSnap.docs.isNotEmpty) {
              iterBiz += bSnap.docs.length;
              for (final d in bSnap.docs) {
                final st = d.data()['status']?.toString();
                if (st == 'completed' || st == 'مكتمل') {
                  iterCompleted++;
                } else {
                  iterInProgress++;
                }
              }
            }
          } catch (_) {}

          try {
            final wSnap = await _db.collection('users').doc(u.uid).collection('workers').get();
            if (wSnap.docs.isNotEmpty) {
              iterWorkers += wSnap.docs.length;
            }
          } catch (_) {}
        }

        if (totalBiz == 0 && iterBiz > 0) {
          totalBiz = iterBiz;
          completedBiz = iterCompleted;
          inProgBiz = iterInProgress;
        }
        if (totalWorkers == 0 && iterWorkers > 0) {
          totalWorkers = iterWorkers;
        }
      }

      return DashboardStats(
        totalUsers: users.length,
        newUsers7: new7,
        newUsers30: new30,
        activeUsers7: active7,
        activeUsers30: active30,
        totalBusinesses: totalBiz,
        completedBusinesses: completedBiz,
        inProgressBusinesses: inProgBiz,
        businessesToday: 0,
        remainingBusinesses: totalBiz - completedBiz,
        totalWorkers: totalWorkers,
        versionDistribution: versionDist,
        statsUpdatedAt: now,
      );
    } catch (_) {
      return null;
    }
  }

  // ===================== المديرون =====================
  Future<List<AdminMember>> fetchAdmins() async {
    final snap = await _db.collection('admin_users').orderBy('createdAt', descending: true).get();
    return snap.docs.map(AdminMember.fromDoc).toList();
  }

  /// بث مباشر لقائمة المديرين — تعكس أي تغيير فوري (خصوصاً مع أكثر من
  /// Super Admin في نفس الوقت) حسب المواصفات.
  Stream<QuerySnapshot<Map<String, dynamic>>> adminUsersStream() {
    return _db.collection('admin_users').orderBy('createdAt', descending: true).snapshots();
  }

  // ===================== الإشعارات =====================
  Future<List<NotificationRequest>> fetchNotifications({int limit = 50}) async {
    final snap = await _db
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(NotificationRequest.fromDoc).toList();
  }

  /// بث مباشر لآخر الإشعارات — يُحدِّث حالة السجل تلقائياً
  /// (من "قيد الإرسال" إلى "مكتمل/فشل جزئي") دون تحديث يدوي.
  Stream<QuerySnapshot<Map<String, dynamic>>> notificationsStream({int limit = 50}) {
    return _db
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Future<String> createNotification({
    required String title,
    required String body,
    required String targetType,
    String? targetUid,
    required String createdBy,
  }) async {
    final ref = await _db.collection('notifications').add({
      'title': title,
      'body': body,
      'targetType': targetType,
      if (targetUid != null) 'targetUid': targetUid,
      'status': 'pending',
      'sentCount': 0,
      'failureCount': 0,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  // ===================== سجل العمليات =====================
  Future<List<AuditLogEntry>> fetchAuditLogs({int limit = 100}) async {
    final snap = await _db
        .collection('audit_logs')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map(AuditLogEntry.fromDoc).toList();
  }

  // ===================== الإعدادات =====================
  Future<AppConfig> fetchAppConfig() async {
    final doc = await _db.collection('platform').doc('app_config').get();
    return AppConfig.fromDoc(doc);
  }

  // ============ إجراءات إدارة المستخدم (لـ Super Admin فقط) ============

  /// يغيِّر نوع الحساب (admin/user) مباشرة في قاعدة البيانات —
  /// التطبيق والقواعد يقرآن هذا الحقل لتحديد الدور.
  Future<void> setUserType({required String uid, required String userType}) async {
    await _db.collection('users').doc(uid).set({
      'userType': userType,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

/// يعلّق/يلغي تعليق حساب مستخدم.
///
/// `status` و`isActive` يُكتبان في العملية نفسها (Atomic) — لا يمكن أن
/// يتعارضا، فإما أن يرى القارئ "موقوف" من الحقلين معاً أو لا يرى تغييراً.
/// `isActive` هو Bool صريح في قاعدة البيانات كما هو مطلوب.
Future<void> setUserBlockedStatus({required String uid, required bool blocked}) async {
    await _db.collection('users').doc(uid).set({
      'status': blocked ? 'suspended' : 'active',
      'isActive': !blocked,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// إزالة عضوية المدير من admin_users عند إلغاء صلاحية المدير.
  Future<void> clearAdminMembership(String uid) async {
    try {
      await _db.collection('admin_users').doc(uid).update({
        'status': 'removed',
        'role': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // الوثيقة غير موجودة — لا مشكلة
    }
  }

  /// حذف/إزالة عضوية مدير عبر قاعدة البيانات (بدون Cloud Function):
  /// users/{uid}.userType ← 'user' وقلب حالة admin_users إلى removed.
  Future<void> removeDbAdminRole(String uid) async {
    try {
      await _db.collection('users').doc(uid).update({
        'userType': 'user',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // الوثيقة غير موجودة — لا مشكلة
    }
    try {
      await _db.collection('admin_users').doc(uid).update({
        'status': 'removed',
        'role': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  /// تعيين دور مدير عبر قاعدة البيانات (يعمل بدون Cloud Functions):
  /// يحدّث حقل userType في وثيقة المستخدم + وثيقة admin_users.
  Future<void> setDbAdminRole({
    required String uid,
    required String role,
    required String email,
    required String displayName,
  }) async {
    // حقل userType في وثيقة المستخدم (الذي يقرأه التطبيق والقواعد)
    final userType = (role == 'super_admin' || role == 'admin') ? role : 'user';
    await _db.collection('users').doc(uid).set({
      'userType': userType,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    await _db.collection('admin_users').doc(uid).set({
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'role': role,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// تسجيل حدث في سجل العمليات (يسمح به Rules للمديرين).
  Future<void> addAuditLog({
    required String actorUid,
    required String action,
    required String result,
    Map<String, dynamic>? details,
  }) async {
    try {
      final actorEmail = FirebaseAuth.instance.currentUser?.email ?? '-';
      await _db.collection('audit_logs').add({
        'actorUid': actorUid,
        'actorEmail': actorEmail,
        'action': action,
        'result': result,
        'details': details ?? {},
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // سجل العمليات غير متاح — لا نوقف العملية
    }
  }

  /// قراءة إحصائيات استهلاك الفايربيس (قراءات، كتابات، حذف، أحداث الحسابات، وحجم التخزين) من جدول Firestore المباشر.
  Future<FirestoreDbUsage> fetchFirestoreDbUsage({int days = 7}) async {
    try {
      final now = DateTime.now();
      final todayKey = usageDateKey(now);

      // 1. قراءة الإجمالي واليوم الحالي
      final statsDoc = await _db.collection('firebase_usage').doc('stats').get();
      final dailyDoc = await _db.collection('firebase_usage').doc('daily_$todayKey').get();

      final totals = FirestoreOps.fromJson(statsDoc.data());
      final today = FirestoreOps.fromJson(dailyDoc.data());

      final totalsAuth = AuthEventsOps.fromJson(statsDoc.data());
      final todayAuth = AuthEventsOps.fromJson(dailyDoc.data());

      // 2. حساب حجم التخزين الفعلي التقريبي لقواعد بيانات Firestore بالبايتات
      double estimatedStorageBytes = 0;
      try {
        final usersSnap = await _db.collection('users').get();
        for (final doc in usersSnap.docs) {
          final str = doc.data().toString();
          estimatedStorageBytes += str.length * 1.5; // متوسط حجم الحقول بالبايتات مع الفهارس
        }
        if (statsDoc.exists && statsDoc.data() != null) {
          estimatedStorageBytes += statsDoc.data().toString().length * 1.5;
        }
        if (dailyDoc.exists && dailyDoc.data() != null) {
          estimatedStorageBytes += dailyDoc.data().toString().length * 1.5;
        }
        final auditSnap = await _db.collection('audit_logs').limit(100).get();
        for (final doc in auditSnap.docs) {
          final str = doc.data().toString();
          estimatedStorageBytes += str.length * 1.5;
        }
      } catch (_) {}

      // 3. قراءة الأيام الأخيرة
      final dailyPoints = <FirestoreDailyPoint>[];
      for (var i = days - 1; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final dateKey = usageDateKey(date);
        try {
          final doc = await _db.collection('firebase_usage').doc('daily_$dateKey').get();
          dailyPoints.add(FirestoreDailyPoint(
            date: DateTime.utc(date.year, date.month, date.day),
            ops: FirestoreOps.fromJson(doc.data()),
          ));
        } catch (_) {
          dailyPoints.add(FirestoreDailyPoint(
            date: DateTime.utc(date.year, date.month, date.day),
            ops: const FirestoreOps.empty(),
          ));
        }
      }

      return FirestoreDbUsage(
        totals: totals,
        today: today,
        totalsAuth: totalsAuth,
        todayAuth: todayAuth,
        storageBytes: estimatedStorageBytes > 0 ? estimatedStorageBytes : null,
        daily: dailyPoints,
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return FirestoreDbUsage.empty();
    }
  }
}