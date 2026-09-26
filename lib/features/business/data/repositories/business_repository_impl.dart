// ignore_for_file: avoid_print
// lib/features/business/data/repositories/business_repository_impl.dart
// تنفيذ عقد BusinessRepository: ينسّق بين المصدر البعيد (Firestore) والمصدر
// المحلي (SQLite/الملفات/SharedPreferences) وخدمة الاتصال. كل منطق المزامنة
// منقول حرفياً من BusinessModel القديم — لا تغيير في السلوك أو المفاتيح أو
// شروط الاندماج أو قواعد وضع التفويض المقيّد.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/core/constants/app_constants.dart';
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/business_repository.dart';
import '../datasources/business_local_datasource.dart';
import '../datasources/business_remote_datasource.dart';

class BusinessRepositoryImpl implements BusinessRepository {
  BusinessRepositoryImpl({required this.userId});

  final String userId;

  final BusinessRemoteDataSource _remote = BusinessRemoteDataSource.instance;
  final BusinessLocalDataSource _local = BusinessLocalDataSource.instance;

  /// تفويض على مستوى السجل: قائمة معرفات الأعمال المسموح بها (فارغة = الكل).
  List<String> _scopedBusinessIds = const [];

  @override
  void setScopedBusinessIds(List<String> ids) =>
      _scopedBusinessIds = List<String>.from(ids);

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
  Future<List<Map<String, dynamic>>> loadLocalBusinesses() =>
      _local.loadLocalBusinesses(userId);

  @override
  Future<void> saveBusinessesToFile(List<Map<String, dynamic>> businesses) =>
      _local.saveBusinessesToFile(userId, businesses);

  @override
  Future<List<Map<String, dynamic>>> loadLocalTransactions() =>
      _local.loadLocalTransactions(userId);

  @override
  Future<void> saveTransactionsToFile(
          List<Map<String, dynamic>> transactions) =>
      _local.saveTransactionsToFile(userId, transactions);

  // ============================== المزامنة ==============================

  @override
  Future<void> syncWithFirestore(List<Map<String, dynamic>> businesses) async {
    final bool internetAvailable = await _hasInternet();
    if (!internetAvailable) return;

    try {
      // 1. رفع الأعمال غير المتزامنة (في وضع التفويض المقيّد نرفع المفوَّض فقط)
      List<Map<String, dynamic>> unsynced =
          businesses.where((b) => b['synced'] == 0).toList();
      if (_scopedBusinessIds.isNotEmpty) {
        unsynced = unsynced
            .where((b) => _scopedBusinessIds.contains(b['id']?.toString()))
            .toList();
      }
      for (var business in unsynced) {
        await _remote.uploadBusiness(userId, business);
        // تحديث حالة المزامنة
        final index = businesses.indexWhere((e) => e['id'] == business['id']);
        if (index != -1) businesses[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty && _scopedBusinessIds.isEmpty) {
        await _local.saveBusinessesToFile(userId, businesses);
      }

      // 2. تحميل الأعمال من السحاب:
      //   - تفويض على مستوى السجل: جلب المعرّفات الممنوحة فقط عبر
      //     where(documentId, whereIn) حتى تسمح قواعد list لكل وثيقة.
      //   - أول مزامنة على هذا الجهاز: جلب كل شيء، لأن الأعمال القديمة
      //     التي أُنشئت قبل إضافة حقل createdAt لن تعود في استعلام where.
      //   - بعدها: تحميل الزيادات فقط حسب آخر مزامنة.
      final String lastSyncStr = await _getLastSyncTime();
      final DateTime parsedLastSync =
          DateTime.tryParse(lastSyncStr) ?? DateTime.utc(2000, 1, 1);
      final bool isFirstSync = parsedLastSync.isBefore(DateTime.utc(2001, 1, 1));
      final Timestamp lastSyncTime = Timestamp.fromDate(parsedLastSync);
      // تحقق ذاتي ليوم يتيم واحد: لو كان الكاش المحلي قد أُتلف بجلسة
      // مشاركة مقيّدة قديمة (لم يكن يحترم عزل التخزين) يُعاد تنزيل الكل
      // مرة واحدة لصاحب الحساب ثم يُثبَّت العِلم.
      final bool ownerCacheValidated = await SharedPreferences.getInstance()
          .then((p) => p.getBool(PrefKeys.ownerCacheFull(userId)) ?? false);

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> cloudDocs = [];
      if (_scopedBusinessIds.isNotEmpty) {
        cloudDocs.addAll(
            await _remote.fetchBusinessesByRecordIds(userId, _scopedBusinessIds));
      } else {
        final bool needFull = isFirstSync || !ownerCacheValidated;
        if (needFull) {
          cloudDocs.addAll(await _remote.fetchAllBusinesses(userId));
        } else {
          // الجديدة (createdAt) والمعدَّلة (updatedAt) منذ آخر مزامنة:
          // التعديل لا يحرّك createdAt، وبدون التقاط updatedAt لن تصل تعديلات
          // المفوَّضين (أو تعديلات من جهاز آخر) إلى صاحب الحساب أبداً.
          cloudDocs.addAll(
              await _remote.fetchNewBusinessesSince(userId, lastSyncTime));
          cloudDocs.addAll(
              await _remote.fetchUpdatedBusinessesSince(userId, lastSyncTime));
        }
      }

      FirebaseUsageTracker.instance.recordReads(cloudDocs.length);
      int addedCount = 0;
      int mergedCount = 0;
      for (final doc in cloudDocs) {
        final data = doc.data();
        final id = doc.id;
        final index = businesses.indexWhere((e) => e['id'] == id);
        if (index == -1) {
          final newBusiness = {
            'id': id,
            'name': data['name'],
            'description': data['description'],
            'amount': data['amount'],
            'clientPhone': data['clientPhone'] ?? '',
            'status': data['status'],
            'date': data['date'] is Timestamp
                ? (data['date'] as Timestamp).toDate().toIso8601String()
                : data['date'].toString(),
            'customFields': data['customFields'] ?? {},
            'initialPaid': data['initialPaid'] ?? 0,
            'totalPaid': data['totalPaid'] ?? 0,
            'totalExpenses': data['totalExpenses'] ?? 0,
            'remaining': data['remaining'] ??
                (data['amount'] != null ? (data['amount'] as num).toInt() : 0),
            'synced': 1,
            'createdAt': data['createdAt'] != null && data['createdAt'] is Timestamp
                ? (data['createdAt'] as Timestamp).toDate().toIso8601String()
                : DateTime.now().toIso8601String(),
            'createdByLabel': data['createdByLabel'],
            'createdByRole': data['createdByRole'],
            'createdByUid': data['createdByUid'],
            'lastModifiedByLabel': data['lastModifiedByLabel'],
            'lastModifiedByRole': data['lastModifiedByRole'],
            'lastModifiedByUid': data['lastModifiedByUid'],
          };
          businesses.add(newBusiness);
          addedCount++;
        } else if (businesses[index]['synced'] != 0) {
          // عمل قائم ومزامن محلياً: نستقبل آخر نسخة سحابية (تعديل من طرف
          // مفوَّض أو من المالك على جهاز آخر). لا نمسّ عملاً غير متزامن
          // (synced == 0) حتى لا تُفقد تعديلات محلية معلّقة لم تُرفع بعد.
          final local = businesses[index];
          local['name'] = data['name'] ?? local['name'];
          local['description'] = data['description'] ?? local['description'];
          local['amount'] = data['amount'] ?? local['amount'];
          local['clientPhone'] = data['clientPhone'] ?? local['clientPhone'];
          local['status'] = data['status'] ?? local['status'];
          local['customFields'] = data['customFields'] ?? local['customFields'];
          local['initialPaid'] = data['initialPaid'] ?? local['initialPaid'];
          local['totalPaid'] = data['totalPaid'] ?? local['totalPaid'];
          local['totalExpenses'] =
              data['totalExpenses'] ?? local['totalExpenses'];
          local['remaining'] = data['remaining'] ?? local['remaining'];
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

      // في وضع المشاركة المقيّد: تُسقَط الأعمال غير المفوَّضة من قائمة
      // الذاكرة المرسلة فقط (تحميل الحركات يعمل ضمنها) — لا يُحفظ أي ناتج
      // منها في التخزين المحلي أبداً، لأن الكاش محفوظ باسم صاحب الحساب
      // ويتنقّل معه عبر الجلسات؛ وإسقاطه من القرص يُفقد المالك أعماله.
      if (_scopedBusinessIds.isNotEmpty) {
        final allowed = _scopedBusinessIds.toSet();
        businesses.removeWhere((b) => !allowed.contains(b['id']?.toString()));
      }

      // ترتيب حسب التاريخ
      businesses.sort((a, b) {
        try {
          DateTime dateA = DateTime.parse(a['date']);
          DateTime dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        } catch (_) {
          return 0;
        }
      });

      if ((addedCount > 0 || mergedCount > 0) && _scopedBusinessIds.isEmpty) {
        await _local.saveBusinessesToFile(userId, businesses);
      }
      // إثبات اكتمال كاش صاحب الحساب (بعد تنزيل كامل ناجح) — الجلسات المقيّدة
      // لا تلمس هذا العِلم ولا تلمس التخزين أبداً.
      if (_scopedBusinessIds.isEmpty) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(PrefKeys.ownerCacheFull(userId), true);
      }
      await _saveLastSyncTime(DateTime.now().toIso8601String());

      return;
    } catch (e) {
      print('خطأ في المزامنة: $e');
      rethrow;
    }
  }

  @override
  Future<void> syncTransactionsWithFirestore(
      List<Map<String, dynamic>> transactions,
      List<Map<String, dynamic>> businesses) async {
    final bool internetAvailable = await _hasInternet();
    if (!internetAvailable) return;

    try {
      // 1. رفع الحركات غير المتزامنة (فقط لعمل لا يزال ضمن قائمة الأعمال
      //    المعروضة — في وضع المشاركة المقيّد تُرفع حركات الأعمال المفوَّضة فقط).
      final Set<String> knownWorkIds =
          businesses.map((b) => b['id']?.toString()).whereType<String>().toSet();
      final List<Map<String, dynamic>> unsynced = transactions
          .where((t) =>
              t['synced'] == 0 && knownWorkIds.contains(t['workId']?.toString()))
          .toList();
      for (var tx in unsynced) {
        await _remote.uploadTransaction(userId, tx);
        final index = transactions.indexWhere((e) => e['id'] == tx['id']);
        if (index != -1) transactions[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty && _scopedBusinessIds.isEmpty) {
        await _local.saveTransactionsToFile(userId, transactions);
      }

      // 2. تحميل الحركات من السحاب (لكل عمل) — أول مزامنة تجلب الكل حتى
      //    تُلتقط الحركات القديمة التي لا تحمل حقل createdAt.
      final String lastSyncStr = await _getLastSyncTransactionsTime();
      final DateTime parsedLastSync =
          DateTime.tryParse(lastSyncStr) ?? DateTime.utc(2000, 1, 1);
      final bool isFirstSync = parsedLastSync.isBefore(DateTime.utc(2001, 1, 1));
      final Timestamp lastSyncTime = Timestamp.fromDate(parsedLastSync);

      int addedCount = 0;
      for (var business in businesses) {
        final String workId = business['id'].toString();
        final QuerySnapshot<Map<String, dynamic>> cloudTxs = await _remote
            .fetchTransactionsFor(userId, workId,
                since: isFirstSync ? null : lastSyncTime);
        FirebaseUsageTracker.instance.recordReads(cloudTxs.docs.length);

        for (var doc in cloudTxs.docs) {
          final data = doc.data();
          final id = doc.id;
          if (!transactions.any((t) => t['id'] == id)) {
            transactions.add({
              'id': id,
              'workId': workId,
              'type': data['type'],
              'amount': data['amount'],
              'description': data['description'] ?? '',
              'date': data['date'] is Timestamp
                  ? (data['date'] as Timestamp).toDate().toIso8601String()
                  : data['date'].toString(),
              'createdAt': data['createdAt'] is Timestamp
                  ? (data['createdAt'] as Timestamp).toDate().toIso8601String()
                  : DateTime.now().toIso8601String(),
              'synced': 1,
              'createdByLabel': data['createdByLabel'],
              'createdByRole': data['createdByRole'],
              'createdByUid': data['createdByUid'],
            });
            addedCount++;
          }
        }
      }

      // ترتيب الحركات من الأحدث للأقدم حسب تاريخ الحركة
      transactions.sort((a, b) {
        try {
          DateTime dateA = DateTime.parse(a['date']);
          DateTime dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        } catch (_) {
          return 0;
        }
      });

      if (addedCount > 0) {
        await _local.saveTransactionsToFile(userId, transactions);
      }
      await _saveLastSyncTransactionsTime(DateTime.now().toIso8601String());
      return;
    } catch (e) {
      print('خطأ في مزامنة الحركات: $e');
      rethrow;
    }
  }

  // ============================== الحقول المخصصة ==============================

  @override
  Future<List<Map<String, dynamic>>> fetchCustomFields() async {
    // 1) التخزين المحلي أولاً حتى تظهر الحقول دون اتصال
    List<Map<String, dynamic>> fields = await _local.loadCustomFields(userId);

    // 2) عند توفر الاتصال: جلب من السحاب وتحديث التخزين المحلي
    final bool internetAvailable = await _hasInternet();
    if (internetAvailable) {
      try {
        fields = await _remote.fetchCustomFields(userId);
        await _local.saveCustomFields(userId, fields);
      } catch (e) {
        print('خطأ في جلب الحقول: $e');
        // يبقى المحتوى المحلي كما هو
      }
    }
    return fields;
  }

  // ============================== العمليات على السحاب ==============================

  @override
  Future<void> uploadTransactionToFirestore(Map<String, dynamic> tx) =>
      _remote.uploadTransaction(userId, tx);

  @override
  Future<void> deleteBusinessFromFirestore(String businessId) =>
      _remote.deleteBusiness(userId, businessId);

  @override
  Future<void> deleteBusinessTransactionsFromFirestore(String workId) =>
      _remote.deleteBusinessTransactions(userId, workId);

  @override
  Future<void> deleteTransactionFromFirestore(
          String workId, String transactionId) =>
      _remote.deleteTransaction(userId, workId, transactionId);

  @override
  Future<void> updateBusinessSummaryFirestore(
    String workId, {
    required int totalPaid,
    required int totalExpenses,
    required int remaining,
  }) =>
      _remote.updateBusinessSummary(
        userId,
        workId,
        totalPaid: totalPaid,
        totalExpenses: totalExpenses,
        remaining: remaining,
      );

  @override
  Future<void> saveBusinessToFirestore(
          Map<String, dynamic> business, bool isEditing) =>
      _remote.saveBusiness(userId, business, isEditing);

  // ============================== مؤشرات المزامنة ==============================

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.lastSync('businesses', userId)) ??
        '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.lastSync('businesses', userId), time);
  }

  Future<String> _getLastSyncTransactionsTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PrefKeys.lastSync('transactions', userId)) ??
        '2000-01-01';
  }

  Future<void> _saveLastSyncTransactionsTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.lastSync('transactions', userId), time);
  }
}