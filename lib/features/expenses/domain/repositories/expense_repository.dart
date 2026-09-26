// lib/features/expenses/domain/repositories/expense_repository.dart
// عقد طبقة بيانات المصروفات — تعريفي، لا يعرف شيئاً عن Firebase/SQLite.
abstract class ExpenseRepository {
  // ========== التخزين المحلي ==========
  Future<void> initStorage();

  Future<List<Map<String, dynamic>>> loadLocalExpenses();

  Future<void> saveExpensesToFile(List<Map<String, dynamic>> expenses);

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> expenses);

  // ========== العمليات على السحاب ==========
  Future<void> saveExpenseToFirestore(
      Map<String, dynamic> expense, bool isEditing);

  Future<void> deleteExpenseFromFirestore(String expenseId);
}