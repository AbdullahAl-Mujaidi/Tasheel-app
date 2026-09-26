// ignore_for_file: avoid_print
// lib/model/business_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين القائمين (business_controller / report_controller).
//
// التنفيذ الفعلي انتقل إلى features/business/data:
//   - BusinessRemoteDataSource (كل اتصالات Firestore)
//   - BusinessLocalDataSource  (SQLite + ترحيل JSON + كاش الحقول المخصصة)
//   - BusinessRepositoryImpl   (تنسيق المزامنة والتحميل والحفظ)
//   - BusinessRepository (العقد في domain)
//
// كل استدعاء هنا مجرد تمرير أو وضع حالة محلية (localBusinesses/
// localTransactions) — لا يوجد أي منطق Firestore/SQLite/مزامنة هنا.
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/features/business/data/repositories/business_repository_impl.dart';
import 'package:fkra/features/business/domain/repositories/business_repository.dart';

class BusinessModel {
  final String userId;
  final BusinessRepository _repo;

  List<Map<String, dynamic>> _localBusinesses = [];
  List<Map<String, dynamic>> _localTransactions = [];

  BusinessModel({required this.userId}) : _repo = BusinessRepositoryImpl(userId: userId);

  /// تفويض على مستوى السجل: قائمة معرفات الأعمال المسموح بها (فارغة = الكل).
  void setScopedBusinessIds(List<String> ids) => _repo.setScopedBusinessIds(ids);

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      await _repo.initStorage();
      _localBusinesses = await _repo.loadLocalBusinesses();
      _localTransactions = await _repo.loadLocalTransactions();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> loadLocalBusinesses() async {
    _localBusinesses = await _repo.loadLocalBusinesses();
  }

  Future<void> saveBusinessesToFile(List<Map<String, dynamic>> businesses) =>
      _repo.saveBusinessesToFile(businesses);

  List<Map<String, dynamic>> get localBusinesses => _localBusinesses;

  // ========== تخزين الحركات المالية محلياً ==========
  Future<void> loadLocalTransactions() async {
    _localTransactions = await _repo.loadLocalTransactions();
  }

  Future<void> saveTransactionsToFile(
          List<Map<String, dynamic>> transactions) =>
      _repo.saveTransactionsToFile(transactions);

  List<Map<String, dynamic>> get localTransactions => _localTransactions;

  // ========== الاتصال بالإنترنت ==========
  Future<bool> hasInternet() => ConnectivityService.hasInternet();

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> businesses) =>
      _repo.syncWithFirestore(businesses);

  Future<void> syncTransactionsWithFirestore(
          List<Map<String, dynamic>> transactions,
          List<Map<String, dynamic>> businesses) =>
      _repo.syncTransactionsWithFirestore(transactions, businesses);

  // ========== الحقول المخصصة ==========
  Future<List<Map<String, dynamic>>> fetchCustomFields() =>
      _repo.fetchCustomFields();

  // ========== حذف من السحاب ==========
  Future<void> deleteBusinessFromFirestore(String businessId) =>
      _repo.deleteBusinessFromFirestore(businessId);

  Future<void> deleteBusinessTransactionsFromFirestore(String workId) =>
      _repo.deleteBusinessTransactionsFromFirestore(workId);

  Future<void> deleteTransactionFromFirestore(
          String workId, String transactionId) =>
      _repo.deleteTransactionFromFirestore(workId, transactionId);

  // ========== تحديث الملخص المالي في السحاب ==========
  Future<void> updateBusinessSummaryFirestore(
    String workId, {
    required int totalPaid,
    required int totalExpenses,
    required int remaining,
  }) =>
      _repo.updateBusinessSummaryFirestore(
        workId,
        totalPaid: totalPaid,
        totalExpenses: totalExpenses,
        remaining: remaining,
      );

  // ========== حفظ أو تحديث في السحاب ==========
  Future<void> saveBusinessToFirestore(
          Map<String, dynamic> business, bool isEditing) =>
      _repo.saveBusinessToFirestore(business, isEditing);

  // ========== رفع حركة مالية واحدة إلى السحاب ==========
  Future<void> uploadTransactionToFirestore(Map<String, dynamic> tx) =>
      _repo.uploadTransactionToFirestore(tx);
}