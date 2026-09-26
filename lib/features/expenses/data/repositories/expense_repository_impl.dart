// ignore_for_file: avoid_print
// lib/features/expenses/data/repositories/expense_repository_impl.dart
// تنفيذ عقد ExpenseRepository: تنسيق المزامنة بين Firestore والمصدر المحلي.
// منقول حرفياً من ExpenseModel القديم.
//
// ⚠️ ملاحظة حرجة حول مفتاح آخر مزامنة: الأصل القديم يستخدم المفتاح البسيط
// `last_sync_$userId` (دون `_expenses_`) — ولو غُيّر إلى `last_sync_expenses_$userId`
// لأُعيد تنزيل كل المصروفات عند أول مزامنة بعد التحديث. يُحافظ على المفتاح
// كما هو بالضبط لأنه عقد التخزين الحالي.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_local_datasource.dart';
import '../datasources/expense_remote_datasource.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  ExpenseRepositoryImpl({required this.userId});

  final String userId;

  final ExpenseRemoteDataSource _remote = ExpenseRemoteDataSource.instance;
  final ExpenseLocalDataSource _local = ExpenseLocalDataSource.instance;

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
  Future<List<Map<String, dynamic>>> loadLocalExpenses() =>
      _local.loadLocalExpenses(userId);

  @override
  Future<void> saveExpensesToFile(List<Map<String, dynamic>> expenses) =>
      _local.saveExpensesToFile(userId, expenses);

  // ============================== المزامنة ==============================

  @override
  Future<void> syncWithFirestore(List<Map<String, dynamic>> expenses) async {
    final bool internetAvailable = await _hasInternet();
    if (!internetAvailable) return;

    try {
      // رفع المصروفات غير المتزامنة
      final List<Map<String, dynamic>> unsynced =
          expenses.where((e) => e['synced'] == 0).toList();
      for (var expense in unsynced) {
        await _remote.uploadExpense(userId, expense);
        final index = expenses.indexWhere((e) => e['id'] == expense['id']);
        if (index != -1) expenses[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty) await _local.saveExpensesToFile(userId, expenses);

      // تحميل المصروفات من السحاب — أول مزامنة تجلب الكل حتى تُلتقط
      // المصروفات القديمة التي لا تحمل حقل createdAt.
      final String lastSyncStr = await _getLastSyncTime();
      final DateTime parsedLastSync =
          DateTime.tryParse(lastSyncStr) ?? DateTime.utc(2000, 1, 1);
      final bool isFirstSync = parsedLastSync.isBefore(DateTime.utc(2001, 1, 1));
      final Timestamp lastSyncTime = Timestamp.fromDate(parsedLastSync);

      final cloudExpenses = await _remote.fetchExpenses(
        userId,
        since: isFirstSync ? null : lastSyncTime,
      );
      FirebaseUsageTracker.instance.recordReads(cloudExpenses.length);

      int addedCount = 0;
      for (var doc in cloudExpenses) {
        final data = doc.data();
        final id = doc.id;
        if (!expenses.any((e) => e['id'] == id)) {
          expenses.add({
            'id': id,
            'description': data['description'],
            'amount': data['amount'],
            'category': data['category'],
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
            'createdByLabel': data['createdByLabel'],
            'createdByRole': data['createdByRole'],
            'createdByUid': data['createdByUid'],
            'lastModifiedByLabel': data['lastModifiedByLabel'],
            'lastModifiedByRole': data['lastModifiedByRole'],
            'lastModifiedByUid': data['lastModifiedByUid'],
          });
          addedCount++;
        }
      }

      expenses.sort((a, b) {
        try {
          final da = DateTime.parse(a['date'].toString());
          final db = DateTime.parse(b['date'].toString());
          return db.compareTo(da);
        } catch (_) {
          return 0;
        }
      });
      if (addedCount > 0) await _local.saveExpensesToFile(userId, expenses);
      await _saveLastSyncTime(DateTime.now().toIso8601String());
    } catch (e) {
      print('خطأ في المزامنة: $e');
      rethrow;
    }
  }

  // ============================== العمليات على السحاب ==============================

  @override
  Future<void> saveExpenseToFirestore(
          Map<String, dynamic> expense, bool isEditing) =>
      _remote.saveExpense(userId, expense, isEditing);

  @override
  Future<void> deleteExpenseFromFirestore(String expenseId) =>
      _remote.deleteExpense(userId, expenseId);

  // ============================== مؤشرات المزامنة ==============================

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_sync_$userId') ?? '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_$userId', time);
  }
}