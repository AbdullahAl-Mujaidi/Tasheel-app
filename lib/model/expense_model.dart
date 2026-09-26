// ignore_for_file: avoid_print
// lib/model/expense_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين القائمين (expense_controller / report_controller).
//
// التنفيذ الفعلي انتقل إلى features/expenses/data:
//   - ExpenseRemoteDataSource (اتصالات Firestore)
//   - ExpenseLocalDataSource  (SQLite + ترحيل JSON)
//   - ExpenseRepositoryImpl   (المزامنة)
//   - ExpenseRepository (العقد في domain)
//
// كل استدعاء هنا مجرد تمرير أو وضع حالة محلية (localExpenses) — لا يوجد
// منطق Firebase/SQLite/مزامنة بعد الآن في هذا الملف.
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:fkra/features/expenses/domain/repositories/expense_repository.dart';

class ExpenseModel {
  final String userId;
  final ExpenseRepository _repo;

  List<Map<String, dynamic>> _localExpenses = [];

  ExpenseModel({required this.userId})
      : _repo = ExpenseRepositoryImpl(userId: userId);

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      await _repo.initStorage();
      _localExpenses = await _repo.loadLocalExpenses();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> loadLocalExpenses() async {
    _localExpenses = await _repo.loadLocalExpenses();
  }

  Future<void> saveExpensesToFile(List<Map<String, dynamic>> expenses) =>
      _repo.saveExpensesToFile(expenses);

  List<Map<String, dynamic>> get localExpenses => _localExpenses;

  // ========== الاتصال بالإنترنت ==========
  Future<bool> hasInternet() => ConnectivityService.hasInternet();

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> expenses) =>
      _repo.syncWithFirestore(expenses);

  // ========== حفظ أو تحديث مصروف في السحاب ==========
  Future<void> saveExpenseToFirestore(
          Map<String, dynamic> expense, bool isEditing) =>
      _repo.saveExpenseToFirestore(expense, isEditing);

  // ========== حذف من السحاب ==========
  Future<void> deleteExpenseFromFirestore(String expenseId) =>
      _repo.deleteExpenseFromFirestore(expenseId);
}