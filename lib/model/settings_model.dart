// lib/models/settings_model.dart
// ملاحظة معمارية: هذا الملف أصبح واجهة تخويل (Facade) رفيعة لدعم التوافق
// العكسي مع المتصلين القائمين (settings_controller).
//
// التنفيذ الفعلي انتقل إلى features/settings/data:
//   - SettingsRemoteDataSource (Firebase: المستخدم + الحقول المخصصة + كلمة المرور)
//   - SettingsLocalDataSource  (SQLite + ترحيل JSON + SharedPreferences للمعلّقات)
//   - SettingsRepositoryImpl   (التنسيق والتمرير)
//   - SettingsRepository       (العقد في domain)
//
// كل استدعاء هنا مجرد تمرير — لا يوجد أي منطق Firebase/SQLite/SharedPreferences هنا.
import 'package:fkra/core/network/connectivity_service.dart';
import 'package:fkra/features/settings/data/repositories/settings_repository_impl.dart';
import 'package:fkra/features/settings/domain/repositories/settings_repository.dart';
import 'package:fkra/model/login_model.dart';

class SettingsModel {
  final String userId;
  final SettingsRepository _repo;

  SettingsModel({required this.userId})
      : _repo = SettingsRepositoryImpl(userId: userId);

  // ========== تهيئة التخزين ==========
  Future<void> initStorage() => _repo.initStorage();

  // ========== بيانات المستخدم ==========
  Future<Map<String, dynamic>?> loadCachedUserData() =>
      _repo.loadCachedUserData();

  Future<void> saveUserDataLocally(Map<String, dynamic> userData) =>
      _repo.saveUserDataLocally(userData);

  Future<Map<String, dynamic>?> fetchUserDataFromFirestore() =>
      _repo.fetchUserDataFromFirestore();

  Future<void> updateUserDataInFirestore(Map<String, dynamic> updateData) =>
      _repo.updateUserDataInFirestore(updateData);

  // ========== الحقول المخصصة ==========
  Future<void> propagateCustomFieldToBusinesses(
          String fieldName, dynamic defaultValue) =>
      _repo.propagateCustomFieldToBusinesses(fieldName, defaultValue);

  Future<List<Map<String, dynamic>>> loadCachedCustomFields() =>
      _repo.loadCachedCustomFields();

  Future<void> saveCustomFieldsLocally(List<Map<String, dynamic>> fields) =>
      _repo.saveCustomFieldsLocally(fields);

  Future<List<Map<String, dynamic>>> fetchCustomFieldsFromFirestore() =>
      _repo.fetchCustomFieldsFromFirestore();

  Future<void> addCustomFieldToFirestore(Map<String, dynamic> fieldData) =>
      _repo.addCustomFieldToFirestore(fieldData);

  Future<void> updateCustomFieldInFirestore(
          String fieldId, Map<String, dynamic> updateData) =>
      _repo.updateCustomFieldInFirestore(fieldId, updateData);

  Future<void> saveCustomFieldToFirestore(
    String fieldId,
    Map<String, dynamic> fieldData, {
    bool isNew = false,
  }) =>
      _repo.saveCustomFieldToFirestore(fieldId, fieldData, isNew: isNew);

  Future<void> deleteCustomFieldFromFirestore(String fieldId) =>
      _repo.deleteCustomFieldFromFirestore(fieldId);

  // ========== تغيير كلمة المرور ==========
  Future<void> changePassword(String newPassword) =>
      _repo.changePassword(newPassword);

  // ========== التحديثات المعلقة ==========
  Future<List<Map<String, dynamic>>> loadPendingUpdates() =>
      _repo.loadPendingUpdates();

  Future<void> savePendingUpdates(List<Map<String, dynamic>> pendingUpdates) =>
      _repo.savePendingUpdates(pendingUpdates);

  // ========== عمليات الحقول المخصصة المعلقة (تعمل دون اتصال) ==========
  Future<List<Map<String, dynamic>>> loadPendingCustomFieldOps() =>
      _repo.loadPendingCustomFieldOps();

  Future<void> savePendingCustomFieldOps(List<Map<String, dynamic>> ops) =>
      _repo.savePendingCustomFieldOps(ops);

  // ========== تسجيل الخروج ==========
  Future<void> clearAllLocalData() => _repo.clearAllLocalData();

  Future<void> signOut() async {
    await LoginModel.signOutPlatform();
    await LoginModel.clearSessionPrefs();
  }

  // ========== الاتصال بالإنترنت ==========
  Future<bool> hasInternet() => ConnectivityService.hasInternet();
}