// lib/features/settings/data/repositories/settings_repository_impl.dart
// تنفيذ عقد SettingsRepository: تمرير مباشر بين المصادر المحلية/البعيدة.
// كل منطق التخزين وFirebase في الـ DataSources — لا يوجد منطق هنا.
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_datasource.dart';
import '../datasources/settings_remote_datasource.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  SettingsRepositoryImpl({required this.userId});

  final String userId;

  final SettingsLocalDataSource _local = SettingsLocalDataSource.instance;
  final SettingsRemoteDataSource _remote = SettingsRemoteDataSource.instance;

  // ========== تهيئة التخزين ==========
  @override
  Future<void> initStorage() => _local.initStorage(userId);

  // ========== بيانات المستخدم ==========
  @override
  Future<Map<String, dynamic>?> loadCachedUserData() =>
      _local.loadCachedUserData(userId);

  @override
  Future<void> saveUserDataLocally(Map<String, dynamic> userData) =>
      _local.saveUserDataLocally(userId, userData);

  @override
  Future<Map<String, dynamic>?> fetchUserDataFromFirestore() =>
      _remote.fetchUserData(userId);

  @override
  Future<void> updateUserDataInFirestore(Map<String, dynamic> updateData) =>
      _remote.updateUserData(userId, updateData);

  // ========== الحقول المخصصة ==========
  @override
  Future<void> propagateCustomFieldToBusinesses(
          String fieldName, dynamic defaultValue) =>
      _local.propagateCustomFieldToBusinesses(
          userId, fieldName, defaultValue);

  @override
  Future<List<Map<String, dynamic>>> loadCachedCustomFields() =>
      _local.loadCachedCustomFields(userId);

  @override
  Future<void> saveCustomFieldsLocally(List<Map<String, dynamic>> fields) =>
      _local.saveCustomFieldsLocally(userId, fields);

  @override
  Future<List<Map<String, dynamic>>> fetchCustomFieldsFromFirestore() =>
      _remote.fetchCustomFields(userId);

  @override
  Future<void> addCustomFieldToFirestore(Map<String, dynamic> fieldData) =>
      _remote.addCustomField(userId, fieldData);

  @override
  Future<void> updateCustomFieldInFirestore(
          String fieldId, Map<String, dynamic> updateData) =>
      _remote.updateCustomField(userId, fieldId, updateData);

  @override
  Future<void> saveCustomFieldToFirestore(
    String fieldId,
    Map<String, dynamic> fieldData, {
    bool isNew = false,
  }) =>
      _remote.saveCustomField(userId, fieldId, fieldData, isNew: isNew);

  @override
  Future<void> deleteCustomFieldFromFirestore(String fieldId) =>
      _remote.deleteCustomField(userId, fieldId);

  // ========== تغيير كلمة المرور ==========
  @override
  Future<void> changePassword(String newPassword) =>
      _remote.changePassword(newPassword);

  // ========== التحديثات المعلقة ==========
  @override
  Future<List<Map<String, dynamic>>> loadPendingUpdates() =>
      _local.loadPendingUpdates(userId);

  @override
  Future<void> savePendingUpdates(List<Map<String, dynamic>> pendingUpdates) =>
      _local.savePendingUpdates(userId, pendingUpdates);

  // ========== عمليات الحقول المخصصة المعلقة ==========
  @override
  Future<List<Map<String, dynamic>>> loadPendingCustomFieldOps() =>
      _local.loadPendingCustomFieldOps(userId);

  @override
  Future<void> savePendingCustomFieldOps(List<Map<String, dynamic>> ops) =>
      _local.savePendingCustomFieldOps(userId, ops);

  // ========== تنظيف البيانات عند تسجيل الخروج ==========
  @override
  Future<void> clearAllLocalData() => _local.clearAllLocalData(userId);
}