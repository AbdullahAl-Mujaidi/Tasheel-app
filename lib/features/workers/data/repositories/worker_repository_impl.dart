// ignore_for_file: avoid_print
// lib/features/workers/data/repositories/worker_repository_impl.dart
// تنفيذ عقد WorkerRepository: ينسّق المزامنة بين Firestore والمصدر المحلي،
// ويحتفظ بحارس وضع التفويض المقيّد (لا كتابة على القرص وعدم تقدم مؤشر
// المزامنة). منقول حرفياً من WorkersModel القديم — لا تغيير في السلوك.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/core/constants/app_constants.dart';
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/worker_repository.dart';
import '../datasources/worker_local_datasource.dart';
import '../datasources/worker_remote_datasource.dart';
import '../models/worker_normalizer.dart';

class WorkerRepositoryImpl implements WorkerRepository {
  WorkerRepositoryImpl({required this.userId});

  final String userId;

  final WorkerRemoteDataSource _remote = WorkerRemoteDataSource.instance;
  final WorkerLocalDataSource _local = WorkerLocalDataSource.instance;

  /// تفويض على مستوى السجل: قائمة معرفات العمال المسموح بها (فارغة = الكل).
  List<String> _scopedWorkerIds = const [];

  @override
  void setScopedWorkerIds(List<String> ids) =>
      _scopedWorkerIds = List<String>.from(ids);

  Future<bool> _hasInternet() => ConnectivityService.hasInternet();

  // ============================== التخزين المحلي ==============================

  @override
  Future<void> initStorage() async {
    try {
      await _local.initStorage(userId);
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> loadLocalWorkers() =>
      _local.loadLocalWorkers(userId);

  @override
  Future<void> saveWorkersToFile(List<Map<String, dynamic>> workers) async {
    // في وضع التفويض المقيّد لا تُكتب قائمة العمال على القرص إطلاقاً — الكاش
    // محفوظ باسم صاحب الحساب ويتنقل معه عبر الجلسات، وكتابة قائمة منقّصة تُفقد
    // المالك عماله (نفس درس عزل تخزين الأعمال سابقاً).
    if (_scopedWorkerIds.isNotEmpty) return;
    await _local.saveWorkersToFile(userId, workers);
  }

  // ============================== المزامنة ==============================

  @override
  Future<void> syncWithFirestore(List<Map<String, dynamic>> workers) async {
    final bool internetAvailable = await _hasInternet();
    if (!internetAvailable) return;

    try {
      // رفع العمال غير المتزامنين (في وضع التفويض المقيّد نرفع المفوَّض فقط)
      List<Map<String, dynamic>> unsynced =
          workers.where((w) => w['synced'] == 0).toList();
      if (_scopedWorkerIds.isNotEmpty) {
        unsynced = unsynced
            .where((w) => _scopedWorkerIds.contains(w['id']?.toString()))
            .toList();
      }
      for (var worker in unsynced) {
        await _remote.uploadWorker(userId, worker);
        final index = workers.indexWhere((e) => e['id'] == worker['id']);
        if (index != -1) workers[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty && _scopedWorkerIds.isEmpty) {
        await saveWorkersToFile(workers);
      }

      // تحميل العمال من السحاب:
      //   - تفويض على مستوى السجل: جلب المعرّفات الممنوحة فقط عبر
      //     where(documentId, whereIn) حتى تسمح قواعد list لكل وثيقة.
      //   - أول مزامنة: جلب كل شيء حتى تُلتقط العمال القدماء الذين لا يحملون
      //     حقل createdAt.
      //   - بعدها: تحميل الزيادات فقط حسب آخر مزامنة.
      final String lastSyncStr = await _getLastSyncTime();
      final DateTime parsedLastSync =
          DateTime.tryParse(lastSyncStr) ?? DateTime.utc(2000, 1, 1);
      final bool isFirstSync = parsedLastSync.isBefore(DateTime.utc(2001, 1, 1));
      final Timestamp lastSyncTime = Timestamp.fromDate(parsedLastSync);

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> cloudDocs = [];
      if (_scopedWorkerIds.isNotEmpty) {
        cloudDocs.addAll(
            await _remote.fetchWorkersByRecordIds(userId, _scopedWorkerIds));
      } else {
        if (isFirstSync) {
          cloudDocs.addAll(await _remote.fetchAllWorkers(userId));
        } else {
          // الجدد (createdAt) والمعدَّلون (updatedAt) منذ آخر مزامنة —
          // التعديل لا يحرّك createdAt، وبدونه لن تصل تعديلات المفوضين
          // (أو من جهاز آخر) إلى صاحب الحساب أبداً.
          cloudDocs.addAll(
              await _remote.fetchNewWorkersSince(userId, lastSyncTime));
          cloudDocs.addAll(
              await _remote.fetchUpdatedWorkersSince(userId, lastSyncTime));
        }
      }

      FirebaseUsageTracker.instance.recordReads(cloudDocs.length);
      int addedCount = 0;
      int mergedCount = 0;
      for (final doc in cloudDocs) {
        final data = doc.data();
        final id = doc.id;
        final index = workers.indexWhere((e) => e['id'] == id);
        if (index == -1) {
          final newWorker = <String, dynamic>{
            'id': id,
            'name': data['name'],
            'phone': data['phone'],
            'specialization': data['specialization'],
            'salary': data['salary'],
            'date': data['date'] != null
                ? (data['date'] is Timestamp
                    ? (data['date'] as Timestamp).toDate().toIso8601String()
                    : data['date'].toString())
                : DateTime.now().toIso8601String(),
            'synced': 1,
            'createdAt': data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate().toIso8601String()
                : data['createdAt']?.toString() ??
                    DateTime.now().toIso8601String(),
            'wageType': data['wageType'] ?? 'monthly',
            'status': data['status'] ?? 'active',
            'businessId': data['businessId'],
            'workRecords': castNestedList(data['workRecords']),
            'payments': castNestedList(data['payments']),
            'advances': castNestedList(data['advances']),
            'workerExpenses': castNestedList(data['workerExpenses']),
            'createdByLabel': data['createdByLabel'],
            'createdByRole': data['createdByRole'],
            'createdByUid': data['createdByUid'],
            'lastModifiedByLabel': data['lastModifiedByLabel'],
            'lastModifiedByRole': data['lastModifiedByRole'],
            'lastModifiedByUid': data['lastModifiedByUid'],
          };
          applyWorkerDefaults(newWorker);
          workers.add(newWorker);
          addedCount++;
        } else if (workers[index]['synced'] != 0) {
          // عامل قائم ومزامن محلياً: نستقبل آخر نسخة سحابية (تعديل من طرف
          // مفوَّض أو من المالك على جهاز آخر). لا نمسّ عاملاً غير متزامن
          // (synced == 0) حتى لا تُفقد تعديلات محلية معلّقة لم تُرفع بعد.
          final local = workers[index];
          local['name'] = data['name'] ?? local['name'];
          local['phone'] = data['phone'] ?? local['phone'];
          local['specialization'] =
              data['specialization'] ?? local['specialization'];
          local['salary'] = data['salary'] ?? local['salary'];
          local['wageType'] = data['wageType'] ?? local['wageType'];
          local['status'] = data['status'] ?? local['status'];
          if (data['businessId'] != null) {
            local['businessId'] = data['businessId'];
          }
          local['workRecords'] = castNestedList(data['workRecords']);
          local['payments'] = castNestedList(data['payments']);
          local['advances'] = castNestedList(data['advances']);
          local['workerExpenses'] = castNestedList(data['workerExpenses']);
          if (data['date'] is Timestamp) {
            local['date'] =
                (data['date'] as Timestamp).toDate().toIso8601String();
          } else if (data['date'] != null) {
            local['date'] = data['date'].toString();
          }
          local['synced'] = 1;
          local['createdByLabel'] =
              data['createdByLabel'] ?? local['createdByLabel'];
          local['createdByRole'] =
              data['createdByRole'] ?? local['createdByRole'];
          local['createdByUid'] =
              data['createdByUid'] ?? local['createdByUid'];
          local['lastModifiedByLabel'] =
              data['lastModifiedByLabel'] ?? local['lastModifiedByLabel'];
          local['lastModifiedByRole'] =
              data['lastModifiedByRole'] ?? local['lastModifiedByRole'];
          local['lastModifiedByUid'] =
              data['lastModifiedByUid'] ?? local['lastModifiedByUid'];
          mergedCount++;
        }
      }

      // في وضع المشاركة المقيّد: تُسقَط العمال غير المفوَّضين من قائمة الذاكرة
      // المرسلة فقط — لا يُحفظ أي شيء على القرص (الكاش باسم صاحب الحساب)،
      // وتصفية العرض في المتحكم تحسب بقية الحالات (قراية القرص دون اتصال).
      if (_scopedWorkerIds.isNotEmpty) {
        final allowed = _scopedWorkerIds.toSet();
        workers.removeWhere((w) => !allowed.contains(w['id']?.toString()));
      }

      workers.sort((a, b) {
        try {
          final da = DateTime.parse(a['date'].toString());
          final db = DateTime.parse(b['date'].toString());
          return db.compareTo(da);
        } catch (_) {
          return 0;
        }
      });
      if ((addedCount > 0 || mergedCount > 0) && _scopedWorkerIds.isEmpty) {
        await saveWorkersToFile(workers);
      }
      // الجلسات المقيّدة لا تلمس مؤشر آخر مزامنة أيضاً حتى لا تتقدم «أثرة»
      // المالك تقدماً يتجاوز عمالاً لم يُنزَّلوا على هذا الجهاز بعد.
      if (_scopedWorkerIds.isEmpty) {
        await _saveLastSyncTime(DateTime.now().toIso8601String());
      }
    } catch (e) {
      print('خطأ في المزامنة: $e');
      rethrow;
    }
  }

  // ============================== العمليات على السحاب ==============================

  @override
  Future<void> saveWorkerToFirestore(
          Map<String, dynamic> worker, bool isEditing) =>
      _remote.saveWorker(userId, worker, isEditing);

  @override
  Future<void> deleteWorkerFromFirestore(String workerId) =>
      _remote.deleteWorker(userId, workerId);

  // ============================== مؤشرات المزامنة ==============================

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.lastSync('workers', userId)) ?? '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.lastSync('workers', userId), time);
  }
}