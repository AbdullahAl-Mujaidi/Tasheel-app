import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/main.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class SettingsPage extends StatefulWidget {
  final String userId;
  const SettingsPage({super.key, required this.userId});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final firestore = FirebaseFirestore.instance;
  final FirebaseAuth auth = FirebaseAuth.instance;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyPassword = GlobalKey<FormState>();
  final GlobalKey<FormState> _formKeyProfile = GlobalKey<FormState>();

  String name = '';
  String email = '';
  String phone = '';
  String businessName = '';
  bool isLoading = true;
  bool isOffline = false;

  // ملفات التخزين
  File? _userDataFile;
  File? _customFieldsFile;
  List<Map<String, dynamic>> customFieldsList = [];
  
  // قوائم التحديثات المعلقة
  List<Map<String, dynamic>> _pendingUpdates = [];

  TextEditingController newPasswordController = TextEditingController();
  TextEditingController confirmPasswordController = TextEditingController();

  TextEditingController nameController = TextEditingController();
  TextEditingController emailController = TextEditingController();
  TextEditingController phoneController = TextEditingController();
  TextEditingController businessNameController = TextEditingController();

  TextEditingController newFieldNameController = TextEditingController();
  List<String> newFieldOptions = [];
  TextEditingController optionInputController = TextEditingController();
  TextEditingController textInputController = TextEditingController();
  TextEditingController numberOptionController = TextEditingController();
  bool isRequired = false;

  String? selectedFieldType;
  List<String> fieldTypes = ['نص', 'رقم', 'تاريخ', 'قائمة منسدلة'];

  Timer? _syncTimer;
  
  // متغيرات للتعديل
  String? _editingFieldId;
  bool _isEditingField = false;

  @override
  void initState() {
    super.initState();
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📱 SettingsPage - Initialized');
    print('👤 UserId: ${widget.userId}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    _initStorage();
    _checkConnectivity();
    _startPeriodicSync();
  }

  // ==================== تهيئة التخزين في الملفات ====================
  Future<void> _initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String settingsDirPath = path.join(appDir.path, 'settings_data');
      
      // إنشاء المجلد إذا لم يكن موجوداً
      final Directory settingsDir = Directory(settingsDirPath);
      if (!await settingsDir.exists()) {
        await settingsDir.create(recursive: true);
        print('📁 تم إنشاء مجلد الإعدادات: $settingsDirPath');
      }
      
      // مسار ملف بيانات المستخدم
      final String userDataPath = path.join(settingsDirPath, 'user_${widget.userId}.json');
      _userDataFile = File(userDataPath);
      
      // مسار ملف الحقول المخصصة
      final String customFieldsPath = path.join(settingsDirPath, 'custom_fields_${widget.userId}.json');
      _customFieldsFile = File(customFieldsPath);
      
      print('📁 مسار ملف بيانات المستخدم: $userDataPath');
      print('📁 مسار ملف الحقول المخصصة: $customFieldsPath');
      
      await _loadCachedUserData();
      await _loadCachedCustomFields();
      await fetchUserData();
      await fetchCustomFields();

      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    } catch (e) {
      print('❌ خطأ في تهيئة التخزين: $e');
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ==================== تحميل بيانات المستخدم من الملف ====================
  Future<void> _loadCachedUserData() async {
    if (_userDataFile == null) return;

    try {
      if (await _userDataFile!.exists()) {
        final String jsonString = await _userDataFile!.readAsString();
        final Map<String, dynamic> userData = jsonDecode(jsonString);
        
        setState(() {
          name = userData['fullName'] ?? 'غير محدد';
          email = userData['email'] ?? 'غير محدد';
          phone = userData['phoneNumber'] ?? 'غير محدد';
          businessName = userData['businessName'] ?? 'غير محدد';
          nameController.text = name;
          emailController.text = email;
          phoneController.text = phone;
          businessNameController.text = businessName;
        });
        
        print('📱 تم تحميل بيانات المستخدم من الملف المحلي');
      }
    } catch (e) {
      print('❌ خطأ في تحميل البيانات من الملف: $e');
    }
  }

  // ==================== حفظ بيانات المستخدم في الملف ====================
  Future<void> _saveUserDataLocally() async {
    if (_userDataFile == null) return;

    try {
      final userData = {
        'fullName': name,
        'email': email,
        'phoneNumber': phone,
        'businessName': businessName,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
      await _userDataFile!.writeAsString(jsonEncode(userData));
      print('💾 تم حفظ بيانات المستخدم في الملف');
    } catch (e) {
      print('❌ خطأ في حفظ البيانات في الملف: $e');
    }
  }

  // ==================== تحميل الحقول المخصصة من الملف ====================
  Future<void> _loadCachedCustomFields() async {
    if (_customFieldsFile == null) return;

    try {
      if (await _customFieldsFile!.exists()) {
        final String jsonString = await _customFieldsFile!.readAsString();
        final List<dynamic> fieldsList = jsonDecode(jsonString);
        setState(() {
          customFieldsList = fieldsList.cast<Map<String, dynamic>>();
        });
        print('📱 تم تحميل ${customFieldsList.length} حقل مخصص من الملف المحلي');
      }
    } catch (e) {
      print('❌ خطأ في تحميل الحقول المخصصة من الملف: $e');
    }
  }

  // ==================== حفظ الحقول المخصصة في الملف ====================
  Future<void> _saveCustomFieldsLocally() async {
    if (_customFieldsFile == null) return;

    try {
      await _customFieldsFile!.writeAsString(jsonEncode(customFieldsList));
      print('💾 تم حفظ ${customFieldsList.length} حقل مخصص في الملف');
    } catch (e) {
      print('❌ خطأ في حفظ الحقول المخصصة في الملف: $e');
    }
  }

  // ==================== تحميل التحديثات المعلقة ====================
  Future<void> _loadPendingUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingJson = prefs.getString('pending_updates_${widget.userId}');
      if (pendingJson != null) {
        _pendingUpdates = List<Map<String, dynamic>>.from(jsonDecode(pendingJson));
        print('📋 يوجد ${_pendingUpdates.length} تحديث معلق');
      }
    } catch (e) {
      print('❌ خطأ في تحميل التحديثات المعلقة: $e');
    }
  }

  // ==================== حفظ التحديثات المعلقة ====================
  Future<void> _savePendingUpdates() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pending_updates_${widget.userId}',
        jsonEncode(_pendingUpdates),
      );
    } catch (e) {
      print('❌ خطأ في حفظ التحديثات المعلقة: $e');
    }
  }

  // ==================== التحقق من الاتصال بالإنترنت ====================
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } on TimeoutException catch (_) {
      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkConnectivity() async {
    final hasInternet = await _hasInternet();
    if (mounted) {
      setState(() {
        isOffline = !hasInternet;
      });
      if (hasInternet) {
        await _syncWithFirestore();
      }
    }
  }

  // ==================== المزامنة الدورية ====================
  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _hasInternet();
      if (hasInternet) {
        await _syncWithFirestore();
      }
    });
  }

  // ==================== المزامنة مع Firebase ====================
  Future<void> _syncWithFirestore() async {
    final bool hasInternet = await _hasInternet();
    if (!hasInternet) return;

    try {
      // 1. مزامنة تحديثات المستخدم
      await _loadPendingUpdates();
      
      if (_pendingUpdates.isNotEmpty) {
        for (var updateData in _pendingUpdates) {
          try {
            await firestore
                .collection('users')
                .doc(widget.userId)
                .update(updateData);
            print('✅ تم مزامنة تحديث: $updateData');
          } catch (e) {
            print('❌ خطأ في مزامنة التحديث: $e');
          }
        }
        _pendingUpdates.clear();
        await _savePendingUpdates();
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ تم مزامنة التحديثات مع الخادم'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // 2. مزامنة الحقول المخصصة
      await fetchCustomFields();
      
    } catch (e) {
      print('❌ خطأ في المزامنة: $e');
    }
  }

  // ==================== جلب بيانات المستخدم ====================
  Future<void> fetchUserData() async {
    final bool hasInternet = await _hasInternet();
    
    if (!hasInternet) {
      // عرض البيانات من الملف المحلي
      await _loadCachedUserData();
      return;
    }

    try {
      DocumentSnapshot userDoc = await firestore
          .collection('users')
          .doc(widget.userId)
          .get();

      if (userDoc.exists) {
        setState(() {
          name = userDoc['fullName'] ?? 'غير محدد';
          email = userDoc['email'] ?? 'غير محدد';
          phone = userDoc['phoneNumber'] ?? 'غير محدد';
          businessName = userDoc['businessName'] ?? 'غير محدد';
          nameController.text = name;
          emailController.text = email;
          phoneController.text = phone;
          businessNameController.text = businessName;
        });
        await _saveUserDataLocally();
      }
    } catch (e) {
      print('خطأ في جلب البيانات: $e');
      await _loadCachedUserData();
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  // ==================== جلب الحقول المخصصة ====================
  Future<void> fetchCustomFields() async {
    final bool hasInternet = await _hasInternet();
    
    if (!hasInternet) {
      await _loadCachedCustomFields();
      return;
    }

    try {
      QuerySnapshot snapshot = await firestore
          .collection('users')
          .doc(widget.userId)
          .collection('custom_fields')
          .orderBy('createdAt', descending: true)
          .get();

      setState(() {
        customFieldsList = snapshot.docs.map((doc) {
          return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
        }).toList();
      });
      
      await _saveCustomFieldsLocally();
    } catch (e) {
      print('خطأ في جلب الحقول: $e');
      await _loadCachedCustomFields();
    }
  }

  // ==================== تحديث معلومات المستخدم ====================
  Future<void> updateInfo() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final bool hasInternet = await _hasInternet();

    Map<String, dynamic> updateData = {
      'fullName': nameController.text,
      'email': emailController.text,
      'phoneNumber': phoneController.text,
      'businessName': businessNameController.text,
    };

    AwesomeDialog(
      context: context,
      dialogType: DialogType.info,
      animType: AnimType.bottomSlide,
      title: 'جاري التحديث',
      desc: 'يرجى الانتظار...',
      dismissOnTouchOutside: false,
      showCloseIcon: false,
    ).show();

    try {
      if (!hasInternet) {
        // حفظ التحديث محلياً للمزامنة لاحقاً
        _pendingUpdates.add(updateData);
        await _savePendingUpdates();

        // تحديث البيانات محلياً
        setState(() {
          name = nameController.text;
          email = emailController.text;
          phone = phoneController.text;
          businessName = businessNameController.text;
        });
        await _saveUserDataLocally();

        if (mounted) {
          Navigator.pop(context);
          AwesomeDialog(
            context: context,
            dialogType: DialogType.info,
            title: '📱 تم الحفظ محلياً',
            desc: 'لا يوجد اتصال بالإنترنت. تم حفظ التحديثات محلياً وسيتم مزامنتها عند عودة الاتصال.',
            btnOkText: 'حسناً',
          ).show();
        }
        return;
      }

      // يوجد إنترنت - تحديث مباشر
      await firestore.collection('users').doc(widget.userId).update(updateData);
      await fetchUserData();

      if (mounted) {
        Navigator.pop(context);
        AwesomeDialog(
          context: context,
          dialogType: DialogType.success,
          animType: AnimType.bottomSlide,
          title: 'تم الحفظ',
          btnOkText: 'حسناً',
          desc: 'تم تحديث البيانات بنجاح',
          btnOkOnPress: () {
            Navigator.pop(context);
          },
        ).show();
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        animType: AnimType.bottomSlide,
        title: 'خطأ',
        desc: 'حدث خطأ أثناء تحديث البيانات: $e',
        btnOkText: 'حسناً',
      ).show();
    }
  }

  // ==================== فتح نافذة تعديل الحقل ====================
  void _openEditField(Map<String, dynamic> field) {
    // تعبئة الحقول بالبيانات الحالية
    newFieldNameController.text = field['fieldName'] ?? '';
    selectedFieldType = field['fieldType'] ?? 'نص';
    isRequired = field['isRequired'] ?? false;
    _editingFieldId = field['id'];
    _isEditingField = true;
    
    // تعبئة القيم الافتراضية حسب النوع
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
    
    // فتح نافذة الإضافة/التعديل
    _showAddEditCustomFieldBottomSheet(Theme.of(context).colorScheme);
  }

  // ==================== إعادة تعيين حالة التعديل ====================
  void _resetFieldEditingState() {
    _editingFieldId = null;
    _isEditingField = false;
    newFieldNameController.clear();
    selectedFieldType = 'نص';
    isRequired = false;
    newFieldOptions.clear();
    textInputController.clear();
    numberOptionController.clear();
    optionInputController.clear();
  }

  // ==================== إضافة أو تحديث حقل مخصص ====================
  Future<void> addOrUpdateCustomField() async {
    if (!_formKeyProfile.currentState!.validate()) {
      return;
    }
    if (newFieldNameController.text.isEmpty) {
      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        title: 'خطأ',
        desc: 'يرجى إدخال اسم الحقل',
      ).show();
      return;
    }

    if (selectedFieldType == 'قائمة منسدلة' && newFieldOptions.isEmpty) {
      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        title: 'خطأ',
        desc: 'يرجى إضافة خيارات للقائمة المنسدلة',
      ).show();
      return;
    }

    final bool hasInternet = await _hasInternet();

    if (!hasInternet) {
      AwesomeDialog(
        context: context,
        dialogType: DialogType.info,
        title: '⚠️ لا يوجد اتصال',
        desc: 'لا يمكن ${_isEditingField ? 'تعديل' : 'إضافة'} الحقول المخصصة حالياً. يرجى الاتصال بالإنترنت والمحاولة مرة أخرى.',
        btnOkText: 'حسناً',
      ).show();
      return;
    }

    AwesomeDialog loadingDialog = AwesomeDialog(
      context: context,
      dialogType: DialogType.info,
      title: _isEditingField ? 'جاري التعديل' : 'جاري الإضافة',
      desc: 'يرجى الانتظار...',
      dismissOnTouchOutside: false,
      showCloseIcon: false,
    )..show();

    try {
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
        'userId': widget.userId,
        'isRequired': isRequired,
        'defaultValue': defaultValue,
      };

      if (selectedFieldType == 'قائمة منسدلة' && newFieldOptions.isNotEmpty) {
        fieldData['options'] = newFieldOptions;
      }

      if (_isEditingField) {
        // تحديث الحقل الموجود
        await firestore
            .collection('users')
            .doc(widget.userId)
            .collection('custom_fields')
            .doc(_editingFieldId)
            .update({
          ...fieldData,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        print('✏️ تم تحديث الحقل: ${newFieldNameController.text}');
      } else {
        // إضافة حقل جديد
        fieldData['createdAt'] = FieldValue.serverTimestamp();
        await firestore
            .collection('users')
            .doc(widget.userId)
            .collection('custom_fields')
            .add(fieldData);
        print('✅ تم إضافة حقل جديد: ${newFieldNameController.text}');
      }

      loadingDialog.dismiss();
      if (mounted) Navigator.pop(context);

      AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        title: _isEditingField ? 'تم التعديل' : 'تم الإضافة',
        desc: _isEditingField ? 'تم تعديل الحقل بنجاح' : 'تم إضافة الحقل بنجاح',
        btnOkText: 'حسناً',
      ).show();

      _resetFieldEditingState();
      await fetchCustomFields();
    } catch (e) {
      loadingDialog.dismiss();
      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        title: 'خطأ',
        desc: 'حدث خطأ: $e',
        btnOkText: 'حسناً',
      ).show();
    }
  }

  // ==================== تغيير كلمة المرور ====================
  Future<void> changePassword() async {
    if (!_formKeyPassword.currentState!.validate()) {
      return;
    }

    final bool hasInternet = await _hasInternet();

    if (!hasInternet) {
      AwesomeDialog(
        context: context,
        dialogType: DialogType.info,
        title: '⚠️ لا يوجد اتصال',
        desc: 'لا يمكن تغيير كلمة المرور حالياً. يرجى الاتصال بالإنترنت والمحاولة مرة أخرى.',
        btnOkText: 'حسناً',
      ).show();
      return;
    }

    AwesomeDialog(
      context: context,
      dialogType: DialogType.info,
      animType: AnimType.bottomSlide,
      title: 'جاري التحديث',
      desc: 'يرجى الانتظار...',
      dismissOnTouchOutside: false,
      showCloseIcon: false,
    ).show();

    try {
      await auth.currentUser!.updatePassword(newPasswordController.text);
      if (mounted) Navigator.pop(context);
      AwesomeDialog(
        context: context,
        dialogType: DialogType.success,
        animType: AnimType.bottomSlide,
        title: 'تم الحفظ',
        btnOkText: 'حسناً',
        desc: 'تم تحديث كلمة المرور بنجاح',
      ).show();

      newPasswordController.clear();
      confirmPasswordController.clear();
    } catch (e) {
      if (mounted) Navigator.pop(context);
      AwesomeDialog(
        context: context,
        dialogType: DialogType.error,
        animType: AnimType.bottomSlide,
        title: 'خطأ',
        desc: 'حدث خطأ أثناء تحديث البيانات: $e',
        btnOkText: 'حسناً',
      ).show();
    }
  }

  // ==================== حذف الحقل المخصص ====================
  void _showDeleteDialog(String fieldId, String fieldName) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      title: 'حذف الحقل',
      desc: 'هل أنت متأكد من حذف الحقل "$fieldName"؟',
      btnOkText: 'نعم، احذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        try {
          await firestore
              .collection('users')
              .doc(widget.userId)
              .collection('custom_fields')
              .doc(fieldId)
              .delete();
          await fetchCustomFields();
          AwesomeDialog(
            context: context,
            dialogType: DialogType.success,
            title: 'تم الحذف',
            desc: 'تم حذف الحقل بنجاح',
            btnOkText: 'حسناً',
          ).show();
        } catch (e) {
          AwesomeDialog(
            context: context,
            dialogType: DialogType.error,
            title: 'خطأ',
            desc: 'حدث خطأ أثناء الحذف: $e',
            btnOkText: 'حسناً',
          ).show();
        }
      },
    ).show();
  }

  // ==================== تسجيل الخروج ====================
  Future<void> _logout(ColorScheme colorScheme) async {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      title: 'تسجيل الخروج',
      desc: 'هل أنت متأكد من رغبتك في تسجيل الخروج؟',
      btnOkText: 'نعم',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        AwesomeDialog(
          context: context,
          dialogType: DialogType.info,
          title: 'جاري تسجيل الخروج',
          desc: 'يرجى الانتظار...',
          dismissOnTouchOutside: false,
          showCloseIcon: false,
        ).show();

        try {
          // تنظيف الملفات المحلية
          if (_userDataFile != null && await _userDataFile!.exists()) {
            await _userDataFile!.delete();
          }
          if (_customFieldsFile != null && await _customFieldsFile!.exists()) {
            await _customFieldsFile!.delete();
          }
          
          // تنظيف SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('logged_in_user');
          await prefs.remove('pending_logins');
          await prefs.remove('pending_updates_${widget.userId}');
          await prefs.remove('cached_stats_${widget.userId}');
          await prefs.remove('cached_top_expenses_${widget.userId}');
          await prefs.remove('cached_business_status_${widget.userId}');
          await prefs.remove('pending_businesses_${widget.userId}');
          await prefs.remove('pending_expenses_${widget.userId}');
          await prefs.remove('last_sync_${widget.userId}');

          // تسجيل الخروج من Firebase
          await FirebaseAuth.instance.signOut();

          if (mounted) {
            Navigator.of(context).pop();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (context) => LoginScreen()),
              (route) => false,
            );
          }
        } catch (e) {
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('حدث خطأ أثناء تسجيل الخروج: $e'),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        }
      },
      btnCancelOnPress: () {},
    ).show();
  }

  // ==================== دوال التحقق ====================
  String? validateFullName(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال الاسم الكامل';
    if (value.length < 3) return 'الاسم يجب أن يكون 3 أحرف على الأقل';
    if (value.length > 50) return 'الاسم طويل جداً';
    return null;
  }

  String? validateBusinessName(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال اسم النشاط التجاري';
    if (value.length < 3) return 'اسم النشاط يجب أن يكون 3 أحرف على الأقل';
    return null;
  }

  String? validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال رقم الهاتف';
    String phone = value.replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^[0-9]+$').hasMatch(phone)) return 'رقم الهاتف يجب أن يحتوي على أرقام فقط';
    if (phone.length < 9 || phone.length > 12) return 'رقم الهاتف غير صحيح (يجب أن يكون 9-12 رقم)';
    return null;
  }

  String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال البريد الإلكتروني';
    String emailPattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$';
    RegExp regex = RegExp(emailPattern);
    if (!regex.hasMatch(value)) return 'البريد الإلكتروني غير صحيح (example@domain.com)';
    return null;
  }

  String? validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال كلمة المرور';
    if (value.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
    if (!RegExp(r'[A-Z]').hasMatch(value)) return 'كلمة المرور يجب أن تحتوي على حرف كبير واحد على الأقل';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'كلمة المرور يجب أن تحتوي على رقم واحد على الأقل';
    if (!RegExp(r'[a-z]').hasMatch(value)) return 'كلمة المرور يجب أن تحتوي على حرف صغير واحد على الأقل';
    return null;
  }

  String? validateConfirmPassword(String? value) {
    if (value == null || value.isEmpty) return 'يرجى تأكيد كلمة المرور';
    if (value != newPasswordController.text) return 'كلمة المرور غير متطابقة';
    return null;
  }

  String? validateNewFieldName(String? value) {
    if (value == null || value.isEmpty) return 'يرجى إدخال اسم الحقل';
    if (value.length < 3) return 'اسم الحقل يجب أن يكون 3 أحرف على الأقل';
    return null;
  }

  String _getFieldTypeName(String? type) {
    switch (type) {
      case 'نص': return 'حقل نصي';
      case 'رقم': return 'حقل رقمي';
      case 'تاريخ': return 'حقل تاريخ';
      case 'قائمة منسدلة': return 'قائمة اختيار';
      default: return 'نص';
    }
  }

  IconData _getFieldTypeIcon(String? type) {
    switch (type) {
      case 'نص': return Icons.text_fields;
      case 'رقم': return Icons.numbers;
      case 'تاريخ': return Icons.calendar_today;
      case 'قائمة منسدلة': return Icons.menu;
      default: return Icons.text_fields;
    }
  }

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

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "تساهيل",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: colorScheme.primary,
            fontSize: 25,
          ),
        ),
        centerTitle: true,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        actions: [
          // زر المزامنة اليدوي
          IconButton(
            onPressed: isOffline ? null : () async {
              AwesomeDialog(
                context: context,
                dialogType: DialogType.info,
                animType: AnimType.bottomSlide,
                title: 'جاري المزامنة',
                desc: 'يرجى الانتظار...',
                dismissOnTouchOutside: false,
                showCloseIcon: false,
              ).show();

              await _syncWithFirestore();
              await fetchUserData();
              await fetchCustomFields();

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ تمت المزامنة بنجاح'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            icon: Icon(Icons.sync, color: isOffline ? Colors.grey : colorScheme.primary),
            tooltip: 'مزامنة مع السحاب',
          ),
          if (isOffline)
            Padding(
              padding: EdgeInsets.all(8),
              child: Tooltip(
                message: 'وضع غير متصل - سيتم حفظ التغييرات محلياً',
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                      SizedBox(width: 4),
                      Text(
                        'غير متصل',
                        style: TextStyle(color: Colors.orange, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator(color: colorScheme.primary))
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (isOffline)
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi_off, color: Colors.orange),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'وضع غير متصل. سيتم حفظ التغييرات محلياً ومزامنتها تلقائياً عند عودة الاتصال. (تغيير كلمة المرور يتطلب اتصال بالإنترنت)',
                              style: TextStyle(color: Colors.orange[700], fontSize: 12),
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Container(
                    margin: EdgeInsets.all(15),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        "الاعدادات",
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                  _buildProfileCard(colorScheme),
                  SizedBox(height: 40),
                  _buildSettingsSection("اعدادات الحساب", colorScheme),
                  _buildSettingsCard(
                    icon: Icons.person,
                    title: "تعديل الملف الشخصي",
                    onTap: () => _showEditProfileBottomSheet(colorScheme),
                    colorScheme: colorScheme,
                  ),
                  _buildSettingsCard(
                    icon: Icons.lock,
                    title: "تغيير كلمة السر",
                    onTap: () => _showChangePasswordBottomSheet(colorScheme),
                    colorScheme: colorScheme,
                  ),
                  _buildCustomFieldsHeader(colorScheme),
                  _buildCustomFieldsList(colorScheme),
                  _buildDangerZone(colorScheme),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileCard(ColorScheme colorScheme) {
    return Container(
      width: 350,
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.primary,
      ),
      child: Column(
        children: [
          CircleAvatar(
            maxRadius: 30,
            backgroundColor: colorScheme.primary.withOpacity(0.3),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '',
              style: TextStyle(color: colorScheme.onPrimary, fontSize: 25),
            ),
          ),
          SizedBox(height: 7),
          Text(name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: colorScheme.onPrimary)),
          SizedBox(height: 7),
          Text(businessName, style: TextStyle(color: colorScheme.onPrimary, fontSize: 19)),
          SizedBox(height: 7),
          Text(phone, style: TextStyle(color: colorScheme.onPrimary, fontSize: 19)),
          SizedBox(height: 7),
          Text(email, style: TextStyle(color: colorScheme.onPrimary, fontSize: 19)),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, ColorScheme colorScheme) {
    return Container(
      margin: EdgeInsets.all(10),
      child: Align(
        alignment: Alignment.centerRight,
        child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
      ),
    );
  }

  Widget _buildSettingsCard({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(vertical: 0, horizontal: 10),
      child: Card(
        color: colorScheme.surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          onTap: onTap,
          title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface), textAlign: TextAlign.right),
          leading: Icon(icon, size: 30, color: colorScheme.primary),
          trailing: Icon(Icons.arrow_back_ios, size: 16, color: colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  void _showEditProfileBottomSheet(ColorScheme colorScheme) {
    showModalBottomSheet(
      isScrollControlled: true,
      showDragHandle: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return Container(
          width: double.infinity,
          child: SingleChildScrollView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
              top: 20,
              left: 10,
              right: 10,
            ),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("تعديل الملف الشخصي", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                  if (isOffline) Padding(
                    padding: EdgeInsets.all(8),
                    child: Text('⚠️ وضع غير متصل - سيتم حفظ التغييرات محلياً', style: TextStyle(color: Colors.orange, fontSize: 12)),
                  ),
                  SizedBox(height: 10),
                  _buildFormField(label: "الاسم الكامل", controller: nameController, validator: validateFullName, icon: Icons.person, colorScheme: colorScheme),
                  _buildFormField(label: "اسم النشاط التجاري", controller: businessNameController, validator: validateBusinessName, icon: Icons.apartment, colorScheme: colorScheme),
                  _buildFormField(label: "البريد الالكتروني", controller: emailController, validator: validateEmail, icon: Icons.email, colorScheme: colorScheme),
                  _buildFormField(label: "رقم الهاتف", controller: phoneController, validator: validatePhone, icon: Icons.phone, colorScheme: colorScheme),
                  SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError, minimumSize: Size(100, 40)),
                        onPressed: () => Navigator.pop(context),
                        child: Text("الغاء"),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary, minimumSize: Size(100, 40)),
                        onPressed: updateInfo,
                        child: Text(isOffline ? "حفظ محلياً" : "حفظ"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required IconData icon,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.only(right: 20, left: 15, top: 10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
          ),
        ),
        Container(
          margin: EdgeInsets.all(15),
          child: TextFormField(
            validator: validator,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            controller: controller,
            cursorColor: colorScheme.primary,
            textAlign: TextAlign.right,
            style: TextStyle(color: colorScheme.onSurface),
            decoration: InputDecoration(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.primary, width: 2)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
              suffixIcon: Icon(icon, color: colorScheme.primary),
            ),
          ),
        ),
      ],
    );
  }

  void _showChangePasswordBottomSheet(ColorScheme colorScheme) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateBottomSheet) {
            bool isPasswordVisible = false;
            bool isConfirmPasswordVisible = false;

            return SingleChildScrollView(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 10, right: 10),
              child: Container(
                margin: EdgeInsets.all(15),
                width: double.infinity,
                child: Form(
                  key: _formKeyPassword,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text("تغيير كلمة السر", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface)),
                      if (isOffline) Padding(
                        padding: EdgeInsets.all(8),
                        child: Text('⚠️ يتطلب تغيير كلمة المرور اتصال بالإنترنت', style: TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                      SizedBox(height: 20),
                      _buildPasswordField(label: "كلمة السر", controller: newPasswordController, validator: validatePassword, obscureText: !isPasswordVisible, onToggle: () => setStateBottomSheet(() => isPasswordVisible = !isPasswordVisible), colorScheme: colorScheme),
                      SizedBox(height: 20),
                      _buildPasswordField(label: "تأكيد كلمة السر", controller: confirmPasswordController, validator: validateConfirmPassword, obscureText: !isConfirmPasswordVisible, onToggle: () => setStateBottomSheet(() => isConfirmPasswordVisible = !isConfirmPasswordVisible), colorScheme: colorScheme),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError, minimumSize: Size(100, 40)),
                            onPressed: () => Navigator.pop(context),
                            child: Text("الغاء"),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: isOffline ? Colors.grey : colorScheme.primary, foregroundColor: colorScheme.onPrimary, minimumSize: Size(100, 40)),
                            onPressed: isOffline ? null : changePassword,
                            child: Text("حفظ"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    required bool obscureText,
    required VoidCallback onToggle,
    required ColorScheme colorScheme,
  }) {
    return Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(label, style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ),
        SizedBox(height: 10),
        TextFormField(
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          controller: controller,
          textAlign: TextAlign.right,
          obscureText: obscureText,
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: label == "كلمة السر" ? '6 احرف على الأقل، مع حرف كبير ورقم' : 'اعد كتابة كلمة السر للتأكيد',
            filled: true,
            fillColor: colorScheme.surface,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline), borderRadius: BorderRadius.circular(10)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(10)),
            suffixIcon: InkWell(onTap: onToggle, child: Icon(obscureText ? Icons.visibility_off : Icons.visibility, color: colorScheme.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomFieldsHeader(ColorScheme colorScheme) {
    return Column(
      children: [
        Container(
          margin: EdgeInsets.only(right: 15, left: 15, top: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ElevatedButton(
                onPressed: isOffline ? null : () => _showAddEditCustomFieldBottomSheet(colorScheme),
                child: Icon(Icons.add, color: colorScheme.onPrimary, size: 18),
                style: ElevatedButton.styleFrom(backgroundColor: isOffline ? Colors.grey : colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              ),
              Text("حقول مخصصة للأعمال", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colorScheme.onSurface)),
            ],
          ),
        ),
        Container(
          margin: EdgeInsets.only(right: 18),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text("حقول اضافية تظهر في نموذج انشاء الاعمال", style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant)),
          ),
        ),
      ],
    );
  }

  // نافذة إضافة/تعديل حقل مخصص
  void _showAddEditCustomFieldBottomSheet(ColorScheme colorScheme) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateBottomSheet) {
            return Form(
              key: _formKeyProfile,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(15),
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isEditingField ? "تعديل حقل" : "إضافة حقل جديد",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      ),
                      SizedBox(height: 20),
                      _buildFormField(label: "اسم الحقل", controller: newFieldNameController, validator: validateNewFieldName, icon: Icons.text_fields, colorScheme: colorScheme),
                      SizedBox(height: 20),
                      Align(alignment: Alignment.centerRight, child: Text("نوع الحقل", style: TextStyle(fontSize: 15, color: colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600))),
                      SizedBox(height: 10),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: DropdownButtonFormField<String>(
                          value: selectedFieldType,
                          decoration: InputDecoration(
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline), borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: colorScheme.surface,
                            prefixIcon: Icon(Icons.question_mark, color: colorScheme.primary),
                          ),
                          items: fieldTypes.map((String item) {
                            return DropdownMenuItem<String>(alignment: Alignment.centerRight, value: item, child: Text(item, style: TextStyle(color: colorScheme.onSurface)));
                          }).toList(),
                          onChanged: (String? newValue) {
                            setStateBottomSheet(() {
                              selectedFieldType = newValue;
                              if (newValue != 'قائمة منسدلة') {
                                newFieldOptions.clear();
                              }
                            });
                          },
                        ),
                      ),
                      if (selectedFieldType == 'قائمة منسدلة') ...[
                        SizedBox(height: 20),
                        _buildInfoCard(Icons.menu, "قائمة اختيار", "اختيار من قائمة خيارات محددة مسبقاً", colorScheme),
                        SizedBox(height: 10),
                        Align(alignment: Alignment.centerRight, child: Text("خيارات القائمة", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
                        SizedBox(height: 10),
                        ...newFieldOptions.asMap().entries.map((entry) {
                          int index = entry.key;
                          String option = entry.value;
                          return Card(
                            color: colorScheme.surface,
                            child: ListTile(
                              leading: IconButton(onPressed: () => setStateBottomSheet(() => newFieldOptions.removeAt(index)), icon: Icon(Icons.delete, color: colorScheme.error)),
                              title: Text(option, style: TextStyle(color: colorScheme.onSurface), textAlign: TextAlign.right),
                              trailing: Text("${index + 1}", style: TextStyle(color: colorScheme.onSurfaceVariant)),
                            ),
                          );
                        }),
                        SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: optionInputController,
                                textAlign: TextAlign.right,
                                style: TextStyle(color: colorScheme.onSurface),
                                decoration: InputDecoration(hintText: 'أدخل خيار جديد', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
                              ),
                            ),
                            SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: () {
                                if (optionInputController.text.isNotEmpty) {
                                  setStateBottomSheet(() {
                                    newFieldOptions.add(optionInputController.text);
                                    optionInputController.clear();
                                  });
                                }
                              },
                              child: Icon(Icons.add),
                              style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary),
                            ),
                          ],
                        ),
                      ],
                      if (selectedFieldType == 'نص') ...[
                        SizedBox(height: 20),
                        _buildInfoCard(Icons.text_fields, "حقل نصي", "حقل لإدخال نصوص حرة", colorScheme),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: textInputController,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'قيمة افتراضية (اختياري)',
                            filled: true,
                            fillColor: colorScheme.surface,
                            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                      if (selectedFieldType == 'رقم') ...[
                        SizedBox(height: 20),
                        _buildInfoCard(Icons.numbers, "حقل رقمي", "حقل لإدخال أرقام فقط", colorScheme),
                        SizedBox(height: 20),
                        TextFormField(
                          controller: numberOptionController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.right,
                          style: TextStyle(color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'قيمة افتراضية (اختياري)',
                            filled: true,
                            fillColor: colorScheme.surface,
                            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: colorScheme.outline)),
                            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("حقل مطلوب", style: TextStyle(color: colorScheme.onSurface)),
                          Switch(value: isRequired, onChanged: (value) => setStateBottomSheet(() => isRequired = value), activeColor: colorScheme.primary),
                        ],
                      ),
                      SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError, minimumSize: Size(100, 40)),
                            onPressed: () {
                              _resetFieldEditingState();
                              Navigator.pop(context);
                            },
                            child: Text("الغاء"),
                          ),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: colorScheme.primary, foregroundColor: colorScheme.onPrimary, minimumSize: Size(100, 40)),
                            onPressed: addOrUpdateCustomField,
                            child: Text(_isEditingField ? "تحديث" : "حفظ"),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildInfoCard(IconData icon, String title, String subtitle, ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: colorScheme.primary.withOpacity(0.1)),
      child: Row(
        children: [
          Icon(icon, color: colorScheme.primary),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                Text(subtitle, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldsList(ColorScheme colorScheme) {
    return Container(
      margin: EdgeInsets.all(15),
      padding: EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: colorScheme.surface,
        boxShadow: [BoxShadow(color: colorScheme.shadow.withOpacity(0.1), spreadRadius: 2, offset: Offset(0, 3))],
      ),
      child: customFieldsList.isEmpty && !isOffline
          ? Center(child: Padding(padding: EdgeInsets.all(20), child: Text("لا توجد حقول مخصصة حتى الآن\nاضغط على زر + لإضافة حقل جديد", textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant))))
          : customFieldsList.isEmpty && isOffline
          ? Center(child: Padding(padding: EdgeInsets.all(20), child: Text("لا توجد حقول مخصصة\nيتطلب إضافة الحقول اتصال بالإنترنت", textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant))))
          : Column(
              children: customFieldsList.map((field) {
                return Container(
                  margin: EdgeInsets.only(bottom: 15),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(onPressed: () => _showDeleteDialog(field['id'], field['fieldName']), icon: Icon(Icons.delete, color: colorScheme.error)),
                              IconButton(
                                onPressed: () => _openEditField(field),
                                icon: Icon(Icons.edit, color: colorScheme.primary),
                                tooltip: 'تعديل الحقل',
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              if (field['isRequired'] == true)
                                Container(padding: EdgeInsets.all(5), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: colorScheme.error.withOpacity(0.1)), child: Text("مطلوب", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.error))),
                              SizedBox(width: 10),
                              Container(
                                padding: EdgeInsets.all(5),
                                decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: colorScheme.primary.withOpacity(0.1)),
                                child: Row(
                                  children: [
                                    Text(_getFieldTypeName(field['fieldType']), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: colorScheme.primary)),
                                    SizedBox(width: 5),
                                    Icon(_getFieldTypeIcon(field['fieldType']), size: 20, color: colorScheme.primary),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      SizedBox(height: 10),
                      Align(alignment: Alignment.centerRight, child: Text(field['fieldName'] ?? 'بدون اسم', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.onSurface))),
                      if (field['fieldType'] == 'قائمة منسدلة' && field['options'] != null && (field['options'] as List).isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 8, right: 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: (field['options'] as List).map((option) {
                                return Chip(label: Text(option.toString()), backgroundColor: colorScheme.surfaceContainerHighest, labelStyle: TextStyle(fontSize: 12, color: colorScheme.onSurface));
                              }).toList(),
                            ),
                          ),
                        ),
                      Divider(height: 20, thickness: 1, color: colorScheme.outline),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildDangerZone(ColorScheme colorScheme) {
    return Column(
      children: [
        Container(padding: EdgeInsets.all(20), child: Align(alignment: Alignment.centerRight, child: Text("منطقة الخطر", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colorScheme.error)))),
        Container(padding: EdgeInsets.only(left: 15, right: 15), child: Divider(color: colorScheme.outline)),
        Container(
          margin: EdgeInsets.only(right: 15, left: 15, top: 15),
          child: TextButton(
            onPressed: () => _logout(colorScheme),
            child: Row(
              children: [
                Spacer(),
                Text("تسجيل الخروج", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.error)),
                SizedBox(width: 10),
                Icon(Icons.logout, color: colorScheme.error),
                Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}