// lib/services/activity_service.dart
// يسجل نشاط المستخدم على وثيقته في Firestore بكفاءة وبدون قراءات زائدة مع كبح زمني (Throttling).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:package_info_plus/package_info_plus.dart';

class ActivityService {
  static final Map<String, DateTime> _lastRecordedTimes = {};

  /// الحد الأدنى بين عمليات تحديث النشاط العادية (15 دقيقة) لتقليل الكتابة في Firestore
  static const Duration throttleDuration = Duration(minutes: 15);

  /// يسجل آخر نشاط للمستخدم مع دعم الكبح الزمني لمنع الكتابة المتكررة
  static Future<void> recordActivity({String? userId, bool force = false}) async {
    await record(userId: userId, isActivity: true, force: force);
  }

  /// يسجل آخر تسجيل دخول/نشاط/مزامنة وإصدار التطبيق على وثيقة المستخدم في Firestore.
  /// يتم التعديل مباشرة عبر merge دون الحاجة لقراءة الوثيقة أولاً (0 Reads).
  static Future<void> record({
    String? userId,
    String? method,
    bool isLogin = false,
    bool isActivity = true,
    bool isSync = false,
    bool force = false,
  }) async {
    try {
      final User? user = FirebaseAuth.instance.currentUser;
      final String uid = userId ?? user?.uid ?? '';
      if (uid.isEmpty) return;

      // فحص الكبح الزمني إذا كان التحديث لمجرد النشاط فقط بدون دخول أو مزامنة صريحة
      if (isActivity && !isLogin && !isSync && !force) {
        final lastRecorded = _lastRecordedTimes[uid];
        if (lastRecorded != null && DateTime.now().difference(lastRecorded) < throttleDuration) {
          return; // يتجاوز التحديث للحفاظ على استهلاك الفايربيس
        }
      }

      String appVersion = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      final Map<String, dynamic> data = {
        'appVersion': appVersion,
        'userId': uid,
      };

      if (isLogin) data['lastLoginAt'] = FieldValue.serverTimestamp();
      if (isActivity) data['lastActivityAt'] = FieldValue.serverTimestamp();
      if (isSync) data['lastSyncAt'] = FieldValue.serverTimestamp();
      if (method != null) data['lastLoginMethod'] = method;

      final ref = FirebaseFirestore.instance.collection('users').doc(uid);
      
      // كتابة مباشرة مع دمج الحقول دون استعلام قراءة سابق (0 Reads)
      await ref.set(data, SetOptions(merge: true));
      FirebaseUsageTracker.instance.recordWrite();

      _lastRecordedTimes[uid] = DateTime.now();
    } catch (e) {
      // لا نعيق التطبيق أبداً بسبب فشل تسجيل النشاط
      // ignore: avoid_print
      print('نتجاهل فشل تسجيل النشاط: $e');
    }
  }
}