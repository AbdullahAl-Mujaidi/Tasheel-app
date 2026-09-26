// lib/features/business/domain/repositories/business_repository.dart
// عقد طبقة بيانات الأعمال والحركات المالية والحقول المخصصة.
//
// ملاحظة معمارية: تُمرَّر البيانات كخرائط Map<String, dynamic> لأن كل مسار
// البيانات في التطبيق (المتحكمات/الشاشات) مبني على هذه الخرائط القادمة من
// SQLite/Firestore مباشرة؛ فرض Entities مقيدة هنا سيتطلب إعادة كتابة كل
// المتصلين ويخالف الشرط الأساسي (عدم تغيير السلوك). الاستخلاص الحقيقي هنا:
// عزل Firebase في المصدر البعيد، وعزل SQLite/الملفات في المصدر المحلي،
// وتنسيق المزامنة في الـ Repository.
abstract class BusinessRepository {
  /// تفويض على مستوى السجل: قائمة معرفات الأعمال المسموح بها (فارغة = الكل).
  void setScopedBusinessIds(List<String> ids);

  // ========== التخزين المحلي (الترحيل من JSON) ==========
  Future<void> initStorage();

  Future<List<Map<String, dynamic>>> loadLocalBusinesses();

  Future<void> saveBusinessesToFile(List<Map<String, dynamic>> businesses);

  Future<List<Map<String, dynamic>>> loadLocalTransactions();

  Future<void> saveTransactionsToFile(List<Map<String, dynamic>> transactions);

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> businesses);

  Future<void> syncTransactionsWithFirestore(
      List<Map<String, dynamic>> transactions,
      List<Map<String, dynamic>> businesses);

  // ========== الحقول المخصصة ==========
  Future<List<Map<String, dynamic>>> fetchCustomFields();

  // ========== العمليات على السحاب ==========
  Future<void> uploadTransactionToFirestore(Map<String, dynamic> tx);

  Future<void> deleteBusinessFromFirestore(String businessId);

  Future<void> deleteBusinessTransactionsFromFirestore(String workId);

  Future<void> deleteTransactionFromFirestore(
      String workId, String transactionId);

  Future<void> updateBusinessSummaryFirestore(
    String workId, {
    required int totalPaid,
    required int totalExpenses,
    required int remaining,
  });

  Future<void> saveBusinessToFirestore(
      Map<String, dynamic> business, bool isEditing);
}