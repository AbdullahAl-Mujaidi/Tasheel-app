// lib/controllers/settings_controller.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/model/settings_model.dart';
import 'package:flutter/material.dart';

class SettingsController extends ChangeNotifier {
  final String userId;
  final SettingsModel _model;

  // بيانات المستخدم
  String name = '';
  String email = '';
  String phone = '';
  String businessName = '';

  // الحقول المخصصة
  List<Map<String, dynamic>> customFieldsList = [];

  // حالة التطبيق
  bool isLoading = true;
  bool isOffline = false;

  // التحديثات المعلقة
  List<Map<String, dynamic>> _pendingUpdates = [];

  // متغيرات نافذة الحقل المخصص
  String newFieldName = '';
  String? selectedFieldType;
  bool isRequired = false;
  List<String> newFieldOptions = [];
  String textDefaultValue = '';
  String numberDefaultValue = '';
  String? editingFieldId;
  bool isEditingField = false;

  // متحكمات الحقول (للاستخدام في الـ View)
  final TextEditingController nameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController businessNameController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  final TextEditingController newFieldNameController = TextEditingController();
  final TextEditingController optionInputController = TextEditingController();
  final TextEditingController textInputController = TextEditingController();
  final TextEditingController numberOptionController = TextEditingController();

  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> formKeyPassword = GlobalKey<FormState>();
  final GlobalKey<FormState> formKeyProfile = GlobalKey<FormState>();

  List<String> fieldTypes = ['نص', 'رقم', 'تاريخ', 'قائمة منسدلة'];
  Timer? _syncTimer;

  SettingsController({required this.userId}) : _model = SettingsModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    await _loadCachedData();
    await _checkConnectivity();
    _startPeriodicSync();
    isLoading = false;
    notifyListeners();
  }

  // ========== تحميل البيانات المخزنة ==========
  Future<void> _loadCachedData() async {
    final userData = await _model.loadCachedUserData();
    if (userData != null) {
      name = userData['fullName'] ?? 'غير محدد';
      email = userData['email'] ?? 'غير محدد';
      phone = userData['phoneNumber'] ?? 'غير محدد';
      businessName = userData['businessName'] ?? 'غير محدد';
      _updateControllers();
    }
    customFieldsList = await _model.loadCachedCustomFields();
    _pendingUpdates = await _model.loadPendingUpdates();
    notifyListeners();
  }

  void _updateControllers() {
    nameController.text = name;
    emailController.text = email;
    phoneController.text = phone;
    businessNameController.text = businessName;
  }

  // ========== الاتصال والمزامنة ==========
  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) {
      await _syncWithFirestore();
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        await _syncWithFirestore();
      }
    });
  }

  Future<void> _syncWithFirestore() async {
    final hasInternet = await _model.hasInternet();
    if (!hasInternet) return;

    try {
      // مزامنة التحديثات المعلقة
      if (_pendingUpdates.isNotEmpty) {
        for (var update in _pendingUpdates) {
          await _model.updateUserDataInFirestore(update);
        }
        _pendingUpdates.clear();
        await _model.savePendingUpdates(_pendingUpdates);
      }

      // تحديث البيانات من الخادم
      await fetchUserData();
      await fetchCustomFields();
      notifyListeners();
    } catch (e) {
      print('خطأ في المزامنة: $e');
    }
  }

  // ========== جلب البيانات من Firebase ==========
  Future<void> fetchUserData() async {
    final hasInternet = await _model.hasInternet();
    if (!hasInternet) {
      await _loadCachedData();
      return;
    }

    try {
      final userData = await _model.fetchUserDataFromFirestore();
      if (userData != null) {
        name = userData['fullName'] ?? 'غير محدد';
        email = userData['email'] ?? 'غير محدد';
        phone = userData['phoneNumber'] ?? 'غير محدد';
        businessName = userData['businessName'] ?? 'غير محدد';
        _updateControllers();
        await _model.saveUserDataLocally({
          'fullName': name,
          'email': email,
          'phoneNumber': phone,
          'businessName': businessName,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        notifyListeners();
      }
    } catch (e) {
      print('خطأ في جلب بيانات المستخدم: $e');
      await _loadCachedData();
    }
  }

  Future<void> fetchCustomFields() async {
    final hasInternet = await _model.hasInternet();
    if (!hasInternet) {
      customFieldsList = await _model.loadCachedCustomFields();
      notifyListeners();
      return;
    }

    try {
      customFieldsList = await _model.fetchCustomFieldsFromFirestore();
      await _model.saveCustomFieldsLocally(customFieldsList);
      notifyListeners();
    } catch (e) {
      print('خطأ في جلب الحقول المخصصة: $e');
      customFieldsList = await _model.loadCachedCustomFields();
      notifyListeners();
    }
  }

  // ========== تحديث معلومات المستخدم ==========
  Future<void> updateUserInfo() async {
    if (!formKey.currentState!.validate()) return;

    final hasInternet = await _model.hasInternet();
    Map<String, dynamic> updateData = {
      'fullName': nameController.text,
      'email': emailController.text,
      'phoneNumber': phoneController.text,
      'businessName': businessNameController.text,
    };

    try {
      if (!hasInternet) {
        // حفظ محلياً
        _pendingUpdates.add(updateData);
        await _model.savePendingUpdates(_pendingUpdates);
        name = nameController.text;
        email = emailController.text;
        phone = phoneController.text;
        businessName = businessNameController.text;
        await _model.saveUserDataLocally({
          'fullName': name,
          'email': email,
          'phoneNumber': phone,
          'businessName': businessName,
          'lastUpdated': DateTime.now().toIso8601String(),
        });
        notifyListeners();
        return; // سيتم عرض رسالة من الـ View
      }

      // تحديث مباشر
      await _model.updateUserDataInFirestore(updateData);
      await fetchUserData();
    } catch (e) {
      rethrow;
    }
  }

  // ========== تغيير كلمة المرور ==========
  Future<void> changePassword() async {
    if (!formKeyPassword.currentState!.validate()) return;
    final hasInternet = await _model.hasInternet();
    if (!hasInternet) throw Exception('لا يوجد اتصال بالإنترنت');
    await _model.changePassword(newPasswordController.text);
  }

  // ========== إدارة الحقول المخصصة ==========
  void resetFieldForm() {
    newFieldNameController.clear();
    selectedFieldType = 'نص';
    isRequired = false;
    newFieldOptions.clear();
    textInputController.clear();
    numberOptionController.clear();
    optionInputController.clear();
    editingFieldId = null;
    isEditingField = false;
    notifyListeners();
  }

  void loadFieldForEditing(Map<String, dynamic> field) {
    newFieldNameController.text = field['fieldName'] ?? '';
    selectedFieldType = field['fieldType'] ?? 'نص';
    isRequired = field['isRequired'] ?? false;
    editingFieldId = field['id'];
    isEditingField = true;

    switch (selectedFieldType) {
      case 'نص':
        textInputController.text = field['defaultValue']?.toString() ?? '';
        break;
      case 'رقم':
        numberOptionController.text = field['defaultValue']?.toString() ?? '';
        break;
      case 'قائمة منسدلة':
        newFieldOptions = List<String>.from(field['options'] ?? []);
        break;
    }
    notifyListeners();
  }

  Future<void> addOrUpdateCustomField() async {
    if (!formKeyProfile.currentState!.validate()) return;
    if (newFieldNameController.text.isEmpty) {
      throw Exception('يرجى إدخال اسم الحقل');
    }
    if (selectedFieldType == 'قائمة منسدلة' && newFieldOptions.isEmpty) {
      throw Exception('يرجى إضافة خيارات للقائمة المنسدلة');
    }

    final hasInternet = await _model.hasInternet();
    if (!hasInternet) {
      throw Exception('لا يوجد اتصال بالإنترنت. لا يمكن إضافة أو تعديل الحقول.');
    }

    dynamic defaultValue;
    switch (selectedFieldType) {
      case 'رقم':
        defaultValue = numberOptionController.text.isNotEmpty
            ? double.tryParse(numberOptionController.text) ?? 0
            : 0;
        break;
      case 'تاريخ':
        defaultValue = null;
        break;
      case 'قائمة منسدلة':
        defaultValue = newFieldOptions.isNotEmpty ? newFieldOptions[0] : '';
        break;
      default:
        defaultValue = textInputController.text;
    }

    Map<String, dynamic> fieldData = {
      'fieldName': newFieldNameController.text.trim(),
      'fieldType': selectedFieldType ?? 'نص',
      'userId': userId,
      'isRequired': isRequired,
      'defaultValue': defaultValue,
    };

    if (selectedFieldType == 'قائمة منسدلة' && newFieldOptions.isNotEmpty) {
      fieldData['options'] = newFieldOptions;
    }

    if (isEditingField) {
      fieldData['updatedAt'] = FieldValue.serverTimestamp();
      await _model.updateCustomFieldInFirestore(editingFieldId!, fieldData);
    } else {
      fieldData['createdAt'] = FieldValue.serverTimestamp();
      await _model.addCustomFieldToFirestore(fieldData);
    }

    await fetchCustomFields();
    resetFieldForm();
  }

  Future<void> deleteCustomField(String fieldId) async {
    await _model.deleteCustomFieldFromFirestore(fieldId);
    await fetchCustomFields();
  }

  // ========== تسجيل الخروج ==========
  Future<void> logout() async {
    await _model.clearAllLocalData();
    await _model.signOut();
  }

  // ========== مزامنة يدوية ==========
  Future<void> syncNow() async {
    await _syncWithFirestore();
  }

  // ========== دوال مساعدة للـ View ==========
  void toggleRequired(bool value) {
    isRequired = value;
    notifyListeners();
  }

  void setSelectedFieldType(String? type) {
    selectedFieldType = type;
    if (type != 'قائمة منسدلة') {
      newFieldOptions.clear();
    }
    notifyListeners();
  }

  void addOptionToList() {
    if (optionInputController.text.isNotEmpty) {
      newFieldOptions.add(optionInputController.text);
      optionInputController.clear();
      notifyListeners();
    }
  }

  void removeOptionFromList(int index) {
    newFieldOptions.removeAt(index);
    notifyListeners();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
    businessNameController.dispose();
    newPasswordController.dispose();
    confirmPasswordController.dispose();
    newFieldNameController.dispose();
    optionInputController.dispose();
    textInputController.dispose();
    numberOptionController.dispose();
    super.dispose();
  }
}