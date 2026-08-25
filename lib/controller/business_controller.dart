// lib/controllers/business_controller.dart
import 'dart:async';
import 'package:fkra/model/business_model.dart';
import 'package:flutter/material.dart';

class BusinessController extends ChangeNotifier {
  final String userId;
  final BusinessModel _model;

  // الحالة الأساسية
  List<Map<String, dynamic>> businesses = [];
  List<Map<String, dynamic>> customFieldsList = [];
  bool isOffline = false;
  bool isLoading = true;
  String selectedCategory = "الكل";

  // متغيرات النافذة المنبثقة (الإضافة/التعديل)
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  String businessName = '';
  String businessDescription = '';
  String businessAmount = '';
  String? selectedStatus;
  DateTime date = DateTime.now();

  // الحقول المخصصة - قيمها
  Map<String, dynamic> customFieldsValues = {};
  Map<String, TextEditingController> textControllers = {};
  Map<String, DateTime> dateValues = {};
  Map<String, String?> dropdownValues = {};

  // حالة التعديل
  String? _editingBusinessId;
  bool _isEditing = false;

  Timer? _syncTimer;

  BusinessController({required this.userId})
      : _model = BusinessModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    businesses = List.from(_model.localBusinesses);
    await _checkConnectivity();
    await _fetchCustomFields();
    _startPeriodicSync();
    isLoading = false;
    notifyListeners();
  }

  // ========== الاتصال ==========
  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) await syncWithFirestore();
  }

  // ========== المزامنة ==========
  Future<void> syncWithFirestore() async {
    try {
      await _model.syncWithFirestore(businesses);
      businesses = List.from(_model.localBusinesses);
      notifyListeners();
    } catch (e) {
      print('فشل المزامنة: $e');
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) await syncWithFirestore();
    });
  }

  // ========== الحقول المخصصة ==========
  Future<void> _fetchCustomFields() async {
    customFieldsList = await _model.fetchCustomFields();
    _initializeCustomFieldsControllers();
    notifyListeners();
  }

  void _initializeCustomFieldsControllers() {
    for (var field in customFieldsList) {
      String fieldName = field['fieldName'];
      switch (field['fieldType']) {
        case 'نص':
          if (!textControllers.containsKey(fieldName)) {
            textControllers[fieldName] = TextEditingController();
          }
          break;
        case 'رقم':
          if (!textControllers.containsKey(fieldName)) {
            textControllers[fieldName] = TextEditingController();
          }
          break;
        case 'تاريخ':
          if (!dateValues.containsKey(fieldName)) {
            dateValues[fieldName] = DateTime.now();
          }
          break;
        case 'قائمة منسدلة':
          if (!dropdownValues.containsKey(fieldName)) {
            dropdownValues[fieldName] = null;
          }
          break;
      }
    }
  }

  // ========== عمليات الأعمال ==========
  Future<void> addBusiness(BuildContext context) async {
    // التحقق من صحة النموذج
    if (!formKey.currentState!.validate()) return;

    final businessId = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();

    Map<String, dynamic> businessData = {
      'id': businessId,
      'name': businessName,
      'description': businessDescription,
      'amount': int.tryParse(businessAmount) ?? 0,
      'date': date.toIso8601String(),
      'status': selectedStatus ?? 'قيد الانتظار',
      'customFields': Map.from(customFieldsValues),
      'synced': 0,
      'createdAt': createdAt,
    };

    // إضافة محلياً
    businesses.insert(0, businessData);
    await _model.saveBusinessesToFile(businesses);
    notifyListeners();

    // محاولة الرفع للسحاب
    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.saveBusinessToFirestore(businessData, false);
        // تحديث حالة المزامنة
        final index = businesses.indexWhere((e) => e['id'] == businessId);
        if (index != -1) {
          businesses[index]['synced'] = 1;
          await _model.saveBusinessesToFile(businesses);
        }
        notifyListeners();
      } catch (e) {
        // فشل الرفع - يبقى محلياً
        print('فشل رفع العمل: $e');
      }
    }
    resetForm();
  }

  Future<void> editBusiness(BuildContext context, String businessId) async {
    if (!formKey.currentState!.validate()) return;

    final index = businesses.indexWhere((e) => e['id'] == businessId);
    if (index == -1) return;

    Map<String, dynamic> updatedData = {
      'id': businessId,
      'name': businessName,
      'description': businessDescription,
      'amount': int.tryParse(businessAmount) ?? 0,
      'date': date.toIso8601String(),
      'status': selectedStatus ?? 'قيد الانتظار',
      'customFields': Map.from(customFieldsValues),
      'synced': 0,
      'createdAt': businesses[index]['createdAt'],
    };

    businesses[index] = updatedData;
    await _model.saveBusinessesToFile(businesses);
    notifyListeners();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.saveBusinessToFirestore(updatedData, true);
        businesses[index]['synced'] = 1;
        await _model.saveBusinessesToFile(businesses);
        notifyListeners();
      } catch (e) {
        print('فشل تحديث العمل: $e');
      }
    }
    resetForm();
  }

  Future<void> deleteBusiness(String businessId) async {
    businesses.removeWhere((e) => e['id'] == businessId);
    await _model.saveBusinessesToFile(businesses);
    notifyListeners();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.deleteBusinessFromFirestore(businessId);
      } catch (e) {
        print('فشل حذف العمل من السحاب: $e');
      }
    }
  }

  // ========== تحميل بيانات العمل للتعديل ==========
  void loadBusinessForEditing(Map<String, dynamic> business) {
    businessName = business['name'] ?? '';
    businessDescription = business['description'] ?? '';
    businessAmount = business['amount']?.toString() ?? '0';
    selectedStatus = business['status'] ?? 'قيد الانتظار';
    try {
      date = DateTime.parse(business['date']);
    } catch (_) {
      date = DateTime.now();
    }

    // تعبئة الحقول المخصصة
    if (business['customFields'] != null) {
      Map<String, dynamic> saved = business['customFields'];
      for (var field in customFieldsList) {
        String fieldName = field['fieldName'];
        String fieldType = field['fieldType'];
        if (saved.containsKey(fieldName)) {
          dynamic value = saved[fieldName];
          switch (fieldType) {
            case 'نص':
              if (textControllers.containsKey(fieldName)) {
                textControllers[fieldName]?.text = value?.toString() ?? '';
              }
              customFieldsValues[fieldName] = value;
              break;
            case 'رقم':
              if (textControllers.containsKey(fieldName)) {
                textControllers[fieldName]?.text = value?.toString() ?? '0';
              }
              customFieldsValues[fieldName] = value ?? 0;
              break;
            case 'تاريخ':
              if (value is String) {
                try {
                  dateValues[fieldName] = DateTime.parse(value);
                  customFieldsValues[fieldName] = DateTime.parse(value);
                } catch (_) {
                  dateValues[fieldName] = DateTime.now();
                  customFieldsValues[fieldName] = DateTime.now();
                }
              } else if (value is DateTime) {
                dateValues[fieldName] = value;
                customFieldsValues[fieldName] = value;
              }
              break;
            case 'قائمة منسدلة':
              dropdownValues[fieldName] = value?.toString();
              customFieldsValues[fieldName] = value?.toString();
              break;
          }
        }
      }
    }
    _editingBusinessId = business['id'];
    _isEditing = true;
    notifyListeners();
  }

  void resetForm() {
    businessName = '';
    businessDescription = '';
    businessAmount = '';
    selectedStatus = null;
    date = DateTime.now();
    _editingBusinessId = null;
    _isEditing = false;
    // مسح الحقول المخصصة
    for (var controller in textControllers.values) {
      controller.clear();
    }
    for (var key in dateValues.keys) {
      dateValues[key] = DateTime.now();
    }
    for (var key in dropdownValues.keys) {
      dropdownValues[key] = null;
    }
    customFieldsValues.clear();
    notifyListeners();
  }

  bool get isEditing => _isEditing;
  String? get editingBusinessId => _editingBusinessId;

  // ========== التصفية ==========
  List<Map<String, dynamic>> get filteredBusinesses {
    return businesses.where((business) {
      final matchesCategory =
          selectedCategory == "الكل" || business['status'] == selectedCategory;
      return matchesCategory;
    }).toList();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    for (var controller in textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ========== دوال مساعدة للعرض ==========
  void toggleCategory(String category) {
    selectedCategory = category;
    notifyListeners();
  }

  void setDate(DateTime newDate) {
    date = newDate;
    notifyListeners();
  }

  void setStatus(String? status) {
    selectedStatus = status;
    notifyListeners();
  }

  void setCustomFieldValue(String fieldName, dynamic value) {
    customFieldsValues[fieldName] = value;
    notifyListeners();
  }
}