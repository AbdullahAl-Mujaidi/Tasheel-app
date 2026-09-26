// lib/features/settings/domain/repositories/settings_repository.dart
// عقد طبقة بيانات الإعدادات (ملف المستخدم + الحقول المخصصة + كلمة المرور +
// المعلّقات) — تعريفي، لا يعرف شيئاً عن Firebase/SQLite/SharedPreferences.
abstract class SettingsRepository {
  // ========== تهيئة التخزين ==========
  Future<void> initStorage();

  // ========== بيانات المستخدم ==========
  Future<Map<String, dynamic>?> loadCachedUserData();

  Future<void> saveUserDataLocally(Map<String, dynamic> userData);

  Future<Map<String, dynamic>?> fetchUserDataFromFirestore();

  Future<void> updateUserDataInFirestore(Map<String, dynamic> updateData);

  // ========== الحقول المخصصة ==========
  Future<void> propagateCustomFieldToBusinesses(
      String fieldName, dynamic defaultValue);

  Future<List<Map<String, dynamic>>> loadCachedCustomFields();

  Future<void> saveCustomFieldsLocally(List<Map<String, dynamic>> fields);

  Future<List<Map<String, dynamic>>> fetchCustomFieldsFromFirestore();

  Future<void> addCustomFieldToFirestore(Map<String, dynamic> fieldData);

  Future<void> updateCustomFieldInFirestore(
      String fieldId, Map<String, dynamic> updateData);

  Future<void> saveCustomFieldToFirestore(
    String fieldId,
    Map<String, dynamic> fieldData, {
    bool isNew = false,
  });

  Future<void> deleteCustomFieldFromFirestore(String fieldId);

  // ========== تغيير كلمة المرور ==========
  Future<void> changePassword(String newPassword);

  // ========== التحديثات المعلقة ==========
  Future<List<Map<String, dynamic>>> loadPendingUpdates();

  Future<void> savePendingUpdates(List<Map<String, dynamic>> pendingUpdates);

  // ========== عمليات الحقول المخصصة المعلقة ==========
  Future<List<Map<String, dynamic>>> loadPendingCustomFieldOps();

  Future<void> savePendingCustomFieldOps(List<Map<String, dynamic>> ops);

  // ========== تنظيف البيانات عند تسجيل الخروج ==========
  Future<void> clearAllLocalData();
}