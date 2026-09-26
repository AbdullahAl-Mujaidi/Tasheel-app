// lib/features/workers/domain/repositories/worker_repository.dart
// عقد طبقة بيانات العمال — تعريفي، لا يعرف شيئاً عن Firebase/SQLite.
abstract class WorkerRepository {
  /// تفويض على مستوى السجل: قائمة معرفات العمال المسموح بها (فارغة = الكل).
  void setScopedWorkerIds(List<String> ids);

  // ========== التخزين المحلي ==========
  Future<void> initStorage();

  Future<List<Map<String, dynamic>>> loadLocalWorkers();

  /// حفظ قائمة العمال محلياً. في وضع التفويض المقيّد لا تكتب شيئاً على
  /// القرص مطلقاً (الكاش باسم صاحب الحساب). هذا الحارس داخل الـ Repository
  /// لأن قراره يعتمد على حالة التفويض.
  Future<void> saveWorkersToFile(List<Map<String, dynamic>> workers);

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> workers);

  // ========== العمليات على السحاب ==========
  Future<void> saveWorkerToFirestore(
      Map<String, dynamic> worker, bool isEditing);

  Future<void> deleteWorkerFromFirestore(String workerId);
}