// ignore_for_file: avoid_print
// lib/model/workers_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين القائمين (workers_controller / report_controller).
//
// التنفيذ الفعلي انتقل إلى features/workers/data:
//   - WorkerRemoteDataSource (اتصالات Firestore)
//   - WorkerLocalDataSource  (SQLite + ترحيل JSON + تطبيع الحقول)
//   - WorkerRepositoryImpl   (المزامنة + حارس وضع التفويض المقيّد)
//   - WorkerRepository (العقد في domain)
//
// كل استدعاء هنا مجرد تمرير أو وضع حالة محلية (localWorkers) — لا يوجد
// منطق Firebase/SQLite/مزامنة بعد الآن في هذا الملف.
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/features/workers/data/repositories/worker_repository_impl.dart';
import 'package:fkra/features/workers/domain/repositories/worker_repository.dart';

class WorkersModel {
  final String userId;
  final WorkerRepository _repo;

  List<Map<String, dynamic>> _localWorkers = [];

  WorkersModel({required this.userId})
      : _repo = WorkerRepositoryImpl(userId: userId);

  /// تفويض على مستوى السجل: قائمة معرفات العمال المسموح بها (فارغة = الكل).
  void setScopedWorkerIds(List<String> ids) => _repo.setScopedWorkerIds(ids);

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      await _repo.initStorage();
      _localWorkers = await _repo.loadLocalWorkers();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> loadLocalWorkers() async {
    _localWorkers = await _repo.loadLocalWorkers();
  }

  Future<void> saveWorkersToFile(List<Map<String, dynamic>> workers) =>
      _repo.saveWorkersToFile(workers);

  List<Map<String, dynamic>> get localWorkers => _localWorkers;

  // ========== الاتصال بالإنترنت ==========
  Future<bool> hasInternet() => ConnectivityService.hasInternet();

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> workers) =>
      _repo.syncWithFirestore(workers);

  // ========== حفظ أو تحديث عامل في السحاب ==========
  Future<void> saveWorkerToFirestore(
          Map<String, dynamic> worker, bool isEditing) =>
      _repo.saveWorkerToFirestore(worker, isEditing);

  // ========== حذف من السحاب ==========
  Future<void> deleteWorkerFromFirestore(String workerId) =>
      _repo.deleteWorkerFromFirestore(workerId);
}