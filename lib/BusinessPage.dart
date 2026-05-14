import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class BusinessPage extends StatefulWidget {
  final String userId;

  const BusinessPage({super.key, required this.userId});

  @override
  State<BusinessPage> createState() => _BusinessPageState();
}

class _BusinessPageState extends State<BusinessPage> {
  DateTime date = DateTime.now();
  String? selectedStatus;
  List<String> statusItems = ['مكتمل', 'قيد الانتظار', 'جاري التنفيذ', 'ملغي'];
  String selectedCategory = "الكل";
  List<Map<String, dynamic>> customFieldsList = [];
  Map<String, dynamic> customFieldsValues = {};
  Map<String, TextEditingController> textControllers = {};
  Map<String, DateTime> dateValues = {};
  Map<String, String?> dropdownValues = {};
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  String businessName = '';
  String businessDescription = '';
  String businessAmount = '';

  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  bool isOffline = false;
  bool _isLoading = true;
  File? _businessesFile;
  List<Map<String, dynamic>> _localBusinesses = [];
  Timer? _syncTimer;

  // متغيرات خاصة بالتعديل
  String? _editingBusinessId;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _initStorage();
    _checkConnectivity();
    _startPeriodicSync();
    fetchCustomFields();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    for (var controller in textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // ==================== تهيئة التخزين في الملفات ====================
  Future<void> _initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String businessesDirPath =
          path.join(appDir.path, 'businesses_data');

      // إنشاء المجلد إذا لم يكن موجوداً
      final Directory businessesDir = Directory(businessesDirPath);
      if (!await businessesDir.exists()) {
        await businessesDir.create(recursive: true);
      }

      // مسار ملف الأعمال الخاص بالمستخدم
      final String filePath =
          path.join(businessesDirPath, 'businesses_${widget.userId}.json');
      _businessesFile = File(filePath);
      await _loadLocalBusinesses();
      await _syncWithFirestore();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('❌ خطأ في تهيئة التخزين: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // ==================== تحميل الأعمال من الملف ====================
  Future<void> _loadLocalBusinesses() async {
    if (_businessesFile == null) {
      return;
    }

    try {
      if (await _businessesFile!.exists()) {
        final String jsonString = await _businessesFile!.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _localBusinesses = jsonList.cast<Map<String, dynamic>>();
      } else {
        _localBusinesses = [];
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ خطأ في تحميل الأعمال من الملف: $e');
      _localBusinesses = [];
    }
  }

  // ==================== حفظ الأعمال في الملف ====================
  Future<void> _saveBusinessesToFile() async {
    if (_businessesFile == null) {
      return;
    }

    try {
      final String jsonString = json.encode(_localBusinesses);
      await _businessesFile!.writeAsString(jsonString);
    } catch (e) {
      print('❌ خطأ في حفظ الأعمال في الملف: $e');
      throw e;
    }
  }

  // ==================== التحقق من الاتصال بالإنترنت ====================
  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'google.com',
      ).timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
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
    }

    if (hasInternet) {
      await _syncWithFirestore();
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

  // ==================== المزامنة مع Firestore ====================
  Future<void> _syncWithFirestore() async {
    if (_businessesFile == null) return;

    final bool hasInternet = await _hasInternet();
    if (!hasInternet) return;

    try {
      // 1. رفع الأعمال غير المتزامنة إلى السحاب
      final List<Map<String, dynamic>> unsyncedBusinesses = _localBusinesses
          .where((business) => business['synced'] == 0)
          .toList();
      for (var business in unsyncedBusinesses) {
        try {
          final docRef = firestore
              .collection('users')
              .doc(widget.userId)
              .collection('businesses')
              .doc(business['id']);

          final docSnapshot = await docRef.get();

          if (!docSnapshot.exists) {
            // إزالة البيانات المحلية قبل الرفع
            Map<String, dynamic> firestoreData = Map.from(business);
            firestoreData.remove('id');
            firestoreData.remove('synced');
            firestoreData.remove('localId');

            // تحويل التاريخ إلى Timestamp إذا كان موجوداً
            if (firestoreData['date'] is String) {
              firestoreData['date'] =
                  Timestamp.fromDate(DateTime.parse(firestoreData['date']));
            }

            await docRef.set(firestoreData);
          } else {
            // تحديث العمل الموجود
            Map<String, dynamic> updateData = {
              'name': business['name'],
              'description': business['description'],
              'amount': business['amount'],
              'status': business['status'],
              'date': Timestamp.fromDate(DateTime.parse(business['date'])),
              'customFields': business['customFields'],
              'updatedAt': FieldValue.serverTimestamp(),
            };
            await docRef.update(updateData);
          }

          // تحديث حالة المزامنة في القائمة المحلية
          final index =
              _localBusinesses.indexWhere((e) => e['id'] == business['id']);
          if (index != -1) {
            _localBusinesses[index]['synced'] = 1;
          }
        } catch (e) {
          print('❌ خطأ في رفع العمل ${business['id']}: $e');
        }
      }

      // حفظ التغييرات المحلية بعد رفع الأعمال
      if (unsyncedBusinesses.isNotEmpty) {
        await _saveBusinessesToFile();
      }

      // 2. تحميل الأعمال الجديدة من السحاب
      final lastSyncTime = await _getLastSyncTime();

      final QuerySnapshot cloudBusinesses = await firestore
          .collection('users')
          .doc(widget.userId)
          .collection('businesses')
          .where('createdAt', isGreaterThan: lastSyncTime)
          .get();

      int addedCount = 0;
      for (var doc in cloudBusinesses.docs) {
        final businessData = doc.data() as Map<String, dynamic>;
        final businessId = doc.id;

        final existingBusiness =
            _localBusinesses.any((e) => e['id'] == businessId);

        if (!existingBusiness) {
          final newBusiness = {
            'id': businessId,
            'name': businessData['name'],
            'description': businessData['description'],
            'amount': businessData['amount'],
            'status': businessData['status'],
            'date': businessData['date'] is Timestamp
                ? (businessData['date'] as Timestamp).toDate().toIso8601String()
                : businessData['date'].toString(),
            'customFields': businessData['customFields'] ?? {},
            'synced': 1,
            'createdAt': businessData['createdAt'] != null &&
                    businessData['createdAt'] is Timestamp
                ? (businessData['createdAt'] as Timestamp)
                    .toDate()
                    .toIso8601String()
                : DateTime.now().toIso8601String(),
          };
          _localBusinesses.add(newBusiness);
          addedCount++;
          print('✅ تم تحميل عمل جديد: ${businessData['name']}');
        }
      }

      // ترتيب الأعمال حسب التاريخ
      _localBusinesses.sort((a, b) {
        try {
          DateTime dateA = DateTime.parse(a['date']);
          DateTime dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });

      if (addedCount > 0) {
        await _saveBusinessesToFile();
      }

      await _saveLastSyncTime(DateTime.now().toIso8601String());
      await _loadLocalBusinesses();

      if (mounted && (unsyncedBusinesses.isNotEmpty || addedCount > 0)) {
        String message = '';
        if (unsyncedBusinesses.isNotEmpty)
          message += 'تم رفع ${unsyncedBusinesses.length} عمل';
        if (addedCount > 0) {
          if (message.isNotEmpty) message += ' و ';
          message += 'تم تحميل $addedCount عمل جديد';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $message'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('❌ خطأ في المزامنة: $e');
    }
  }

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_sync_businesses_${widget.userId}') ??
        '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_businesses_${widget.userId}', time);
  }

  // ==================== جلب الحقول المخصصة ====================
  Future<void> fetchCustomFields() async {
    final bool hasInternet = await _hasInternet();

    // محاولة جلب الحقول من Firebase إذا كان هناك إنترنت
    if (hasInternet) {
      try {
        QuerySnapshot snapshot = await firestore
            .collection('users')
            .doc(widget.userId)
            .collection('custom_fields')
            .orderBy('createdAt', descending: false)
            .get();

        setState(() {
          customFieldsList = snapshot.docs.map((doc) {
            return {'id': doc.id, ...doc.data() as Map<String, dynamic>};
          }).toList();

          _initializeCustomFieldsControllers();
        });

        // حفظ الحقول محلياً
        await _saveCustomFieldsLocally();
      } catch (e) {
        print('خطأ في جلب الحقول: $e');
        await _loadCustomFieldsLocally();
      }
    } else {
      // إذا لم يوجد إنترنت، تحميل من الملف المحلي
      await _loadCustomFieldsLocally();
    }
  }

  Future<void> _saveCustomFieldsLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'custom_fields_${widget.userId}',
        jsonEncode(customFieldsList),
      );
    } catch (e) {
      print('خطأ في حفظ الحقول محلياً: $e');
    }
  }

  Future<void> _loadCustomFieldsLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedFields = prefs.getString('custom_fields_${widget.userId}');
      if (cachedFields != null) {
        final List<dynamic> fieldsList = jsonDecode(cachedFields);
        setState(() {
          customFieldsList = fieldsList.cast<Map<String, dynamic>>();
          _initializeCustomFieldsControllers();
        });
      }
    } catch (e) {
      print('خطأ في تحميل الحقول من الملف: $e');
    }
  }

  void _initializeCustomFieldsControllers() {
    for (var field in customFieldsList) {
      String fieldName = field['fieldName'];

      switch (field['fieldType']) {
        case 'نص':
          if (!textControllers.containsKey(fieldName)) {
            textControllers[fieldName] = TextEditingController(
              text: field['defaultValue'] ?? '',
            );
          }
          customFieldsValues[fieldName] = field['defaultValue'] ?? '';
          break;
        case 'رقم':
          if (!textControllers.containsKey(fieldName)) {
            textControllers[fieldName] = TextEditingController(
              text: field['defaultValue']?.toString() ?? '',
            );
          }
          customFieldsValues[fieldName] = field['defaultValue'] ?? 0;
          break;
        case 'تاريخ':
          if (!dateValues.containsKey(fieldName)) {
            dateValues[fieldName] = DateTime.now();
          }
          customFieldsValues[fieldName] = DateTime.now();
          break;
        case 'قائمة منسدلة':
          List<String> options = List<String>.from(field['options'] ?? []);
          if (!dropdownValues.containsKey(fieldName)) {
            dropdownValues[fieldName] = options.isNotEmpty ? options[0] : '';
          }
          customFieldsValues[fieldName] = dropdownValues[fieldName] ?? '';
          break;
      }
    }
  }

  // ==================== فتح نافذة التعديل ====================
  void _openEditBusiness(Map<String, dynamic> business) {
    // تعبئة الحقول بالبيانات الحالية
    businessName = business['name'] ?? '';
    businessDescription = business['description'] ?? '';
    businessAmount = business['amount']?.toString() ?? '0';
    selectedStatus = business['status'] ?? 'قيد الانتظار';

    try {
      date = DateTime.parse(business['date']);
    } catch (e) {
      date = DateTime.now();
    }

    // تعبئة الحقول المخصصة
    if (business['customFields'] != null) {
      Map<String, dynamic> savedCustomFields = business['customFields'];

      for (var field in customFieldsList) {
        String fieldName = field['fieldName'];
        String fieldType = field['fieldType'];

        if (savedCustomFields.containsKey(fieldName)) {
          dynamic value = savedCustomFields[fieldName];

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
                } catch (e) {
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

    // فتح نافذة الإضافة/التعديل
    _showAddEditBusinessBottomSheet(Theme.of(context).colorScheme);
  }

  // ==================== إعادة تعيين حالة التعديل ====================
  void _resetEditingState() {
    _editingBusinessId = null;
    _isEditing = false;
    _clearForm();
  }

  void _clearForm() {
    businessName = '';
    businessDescription = '';
    businessAmount = '';
    selectedStatus = null;
    date = DateTime.now();

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
  }

  // ==================== حفظ أو تحديث العمل ====================
  Future<void> _saveBusiness(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final businessId = _isEditing && _editingBusinessId != null
        ? _editingBusinessId!
        : DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = _isEditing
        ? (_localBusinesses
                .firstWhere((e) => e['id'] == businessId)['createdAt'] ??
            DateTime.now().toIso8601String())
        : DateTime.now().toIso8601String();

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

    AwesomeDialog(
      context: context,
      dialogType: DialogType.info,
      animType: AnimType.bottomSlide,
      title: _isEditing ? 'جاري التعديل' : 'جاري الحفظ',
      desc: 'يرجى الانتظار...',
      dismissOnTouchOutside: false,
      showCloseIcon: false,
    ).show();

    try {
      if (_isEditing) {
        // تعديل العمل الموجود
        final index = _localBusinesses.indexWhere((e) => e['id'] == businessId);
        if (index != -1) {
          _localBusinesses[index] = businessData;
          print('✏️ تم تعديل العمل: $businessName');
        }
      } else {
        // إضافة عمل جديد
        _localBusinesses.insert(0, businessData);
        print('✅ تم إضافة عمل جديد: $businessName');
      }

      // ترتيب الأعمال حسب التاريخ
      _localBusinesses.sort((a, b) {
        try {
          DateTime dateA = DateTime.parse(a['date']);
          DateTime dateB = DateTime.parse(b['date']);
          return dateB.compareTo(dateA);
        } catch (e) {
          return 0;
        }
      });

      await _saveBusinessesToFile();
      await _loadLocalBusinesses();

      final bool hasInternet = await _hasInternet();

      if (hasInternet) {
        try {
          // إزالة الحقول الخاصة بالتخزين المحلي قبل الرفع
          Map<String, dynamic> firestoreData = Map.from(businessData);
          firestoreData.remove('id');
          firestoreData.remove('synced');

          if (_isEditing) {
            // تحديث في السحاب
            await firestore
                .collection('users')
                .doc(widget.userId)
                .collection('businesses')
                .doc(businessId)
                .update({
              ...firestoreData,
              'date': Timestamp.fromDate(date),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            print('✅ تم تحديث العمل في السحاب');
          } else {
            // إضافة جديدة في السحاب
            await firestore
                .collection('users')
                .doc(widget.userId)
                .collection('businesses')
                .doc(businessId)
                .set({
              ...firestoreData,
              'date': Timestamp.fromDate(date),
              'createdAt': FieldValue.serverTimestamp(),
            });
            print('✅ تم إضافة العمل في السحاب');
          }

          // تحديث حالة المزامنة
          final index =
              _localBusinesses.indexWhere((e) => e['id'] == businessId);
          if (index != -1) {
            _localBusinesses[index]['synced'] = 1;
            await _saveBusinessesToFile();
            await _loadLocalBusinesses();
          }

          if (mounted) {
            Navigator.pop(context);
            AwesomeDialog(
              context: context,
              dialogType: DialogType.success,
              animType: AnimType.bottomSlide,
              title: _isEditing ? 'تم التعديل' : 'تم الحفظ',
              btnOkText: 'حسناً',
              desc: _isEditing
                  ? 'تم تعديل بيانات العمل بنجاح (محلياً وسحابياً)'
                  : 'تم حفظ بيانات العمل بنجاح (محلياً وسحابياً)',
              btnOkOnPress: () {
                _resetEditingState();
                Navigator.pop(context);
              },
            ).show();
          }
        } catch (e) {
          if (mounted) {
            Navigator.pop(context);
            AwesomeDialog(
              context: context,
              dialogType: DialogType.warning,
              animType: AnimType.bottomSlide,
              title: 'تنبيه',
              desc: _isEditing
                  ? 'تم تعديل البيانات محلياً، وسيتم رفعها تلقائياً'
                  : 'تم حفظ البيانات محلياً، وسيتم رفعها تلقائياً',
              btnOkText: 'حسناً',
              btnOkOnPress: () {
                _resetEditingState();
                Navigator.pop(context);
              },
            ).show();
          }
        }
      } else {
        if (mounted) {
          Navigator.pop(context);
          AwesomeDialog(
            context: context,
            dialogType: DialogType.warning,
            animType: AnimType.bottomSlide,
            title: _isEditing ? 'تم التعديل محلياً' : 'تم الحفظ محلياً',
            desc:
                'لا يوجد اتصال بالإنترنت. تم ${_isEditing ? 'تعديل' : 'حفظ'} العمل محلياً',
            btnOkText: 'حسناً',
            btnOkOnPress: () {
              _resetEditingState();
              Navigator.pop(context);
            },
          ).show();

          setState(() {
            isOffline = true;
          });
        }
      }
    } catch (error) {
      if (mounted) {
        Navigator.pop(context);
        AwesomeDialog(
          context: context,
          dialogType: DialogType.error,
          animType: AnimType.bottomSlide,
          title: 'خطأ',
          desc:
              'حدث خطأ أثناء ${_isEditing ? 'تعديل' : 'حفظ'} البيانات: $error',
          btnOkText: 'حسناً',
        ).show();
      }
    }
  }

  // ==================== حذف العمل ====================
  Future<void> deleteBusiness(String businessId, String businessName) async {
    if (!mounted) return;

    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد من حذف العمل "$businessName"؟',
      btnOkText: 'حذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        AwesomeDialog(
          context: context,
          dialogType: DialogType.info,
          animType: AnimType.bottomSlide,
          title: 'جاري الحذف',
          desc: 'يرجى الانتظار...',
          dismissOnTouchOutside: false,
          showCloseIcon: false,
        ).show();

        try {
          // حذف العمل من القائمة المحلية
          _localBusinesses
              .removeWhere((business) => business['id'] == businessId);
          await _saveBusinessesToFile();
          await _loadLocalBusinesses();

          final bool hasInternet = await _hasInternet();
          if (hasInternet) {
            await firestore
                .collection('users')
                .doc(widget.userId)
                .collection('businesses')
                .doc(businessId)
                .delete();
          }

          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(" تم حذف العمل بنجاح"),
                backgroundColor: Theme.of(context).colorScheme.primary,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(" حدث خطأ أثناء حذف العمل: $e"),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      },
      btnCancelOnPress: () {},
    ).show();
  }

  // ==================== دوال مساعدة ====================
  String? validateBusinessName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'اسم العمل مطلوب';
    }
    if (value.length < 3) {
      return 'اسم العمل يجب أن يكون 3 أحرف على الأقل';
    }
    if (value.length > 100) {
      return 'اسم العمل طويل جداً';
    }
    return null;
  }

  String? validateBusinessDescription(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'وصف العمل مطلوب';
    }
    if (value.length > 500) {
      return 'الوصف طويل جداً (الحد الأقصى 500 حرف)';
    }
    return null;
  }

  String? validateBusinessAmount(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'المبلغ مطلوب';
    }

    final double? amount = double.tryParse(value);
    if (amount == null) {
      return 'يرجى إدخال رقم صحيح';
    }

    if (amount <= 0) {
      return 'المبلغ يجب أن يكون أكبر من 0';
    }

    if (amount > 999999999) {
      return 'المبلغ كبير جداً';
    }

    return null;
  }

  String _formatDate(dynamic date) {
    if (date is String) {
      try {
        DateTime d = DateTime.parse(date);
        return "${d.day}-${d.month}-${d.year}";
      } catch (e) {
        return '';
      }
    }
    if (date is Timestamp) {
      DateTime d = date.toDate();
      return "${d.day}-${d.month}-${d.year}";
    }
    return '';
  }

  String _formatValue(dynamic value) {
    if (value is DateTime) {
      return "${value.day}-${value.month}-${value.year}";
    }
    return value?.toString() ?? '';
  }

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text("تساهيل", style: TextStyle(color: colorScheme.primary)),
          centerTitle: true,
          backgroundColor: colorScheme.surface,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colorScheme.primary),
              SizedBox(height: 16),
              Text('جاري تحميل الأعمال...',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

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
          // زر المزامنة
          IconButton(
            onPressed: isOffline
                ? null
                : () async {
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

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('تمت المزامنة بنجاح'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
            icon: Icon(Icons.sync,
                color: isOffline ? Colors.grey : colorScheme.primary),
            tooltip: 'مزامنة مع السحاب',
          ),
          if (isOffline)
            Padding(
              padding: EdgeInsets.all(8),
              child: Tooltip(
                message: 'وضع غير متصل - سيتم حفظ الأعمال محلياً',
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
      body: SingleChildScrollView(
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      _resetEditingState();
                      _showAddEditBusinessBottomSheet(colorScheme);
                    },
                    label: Text(
                      "اضافة عمل",
                      style: TextStyle(
                        color: colorScheme.onPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    icon: Icon(Icons.add, color: colorScheme.onPrimary),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                    ),
                  ),
                  Text(
                    "الاعمال",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
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
                        'وضع غير متصل. سيتم حفظ الأعمال الجديدة محلياً ومزامنتها تلقائياً عند عودة الاتصال.',
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(height: 5),
            SizedBox(
              width: 370,
              child: TextFormField(
                textAlign: TextAlign.right,
                onChanged: (value) {
                  setState(() {});
                },
                decoration: InputDecoration(
                  suffixIcon: Icon(Icons.search, color: colorScheme.primary),
                  hintText: "البحث عن عمل",
                  hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                  filled: true,
                  fillColor: colorScheme.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: colorScheme.outline),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(color: colorScheme.outline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 15),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterButton("الكل", "الكل", colorScheme),
                  SizedBox(width: 5),
                  _buildFilterButton(
                      "قيد الانتظار", "قيد الانتظار", colorScheme),
                  SizedBox(width: 5),
                  _buildFilterButton(
                      "جاري التنفيذ", "جاري التنفيذ", colorScheme),
                  SizedBox(width: 5),
                  _buildFilterButton("مكتمل", "مكتمل", colorScheme),
                  SizedBox(width: 5),
                  _buildFilterButton("ملغي", "ملغي", colorScheme),
                ],
              ),
            ),
            if (_localBusinesses.isNotEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'إجمالي الأعمال: ${_getFilteredBusinesses().length}',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    if (_localBusinesses.any((e) => e['synced'] == 0))
                      Container(
                        padding:
                            EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '⚠️ يوجد أعمال غير متزامنة',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            _buildBusinessesList(colorScheme),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _getFilteredBusinesses() {
    return _localBusinesses.where((business) {
      final businessNameLower =
          business['name']?.toString().toLowerCase() ?? '';
      final searchText = ''; // يمكن إضافة searchController لاحقاً
      final matchesSearch = searchText.isEmpty ||
          businessNameLower.contains(searchText.toLowerCase());
      final matchesCategory =
          selectedCategory == "الكل" || business['status'] == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  Widget _buildFilterButton(
    String label,
    String value,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: ElevatedButton(
        onPressed: () {
          setState(() {
            selectedCategory = value;
          });
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: selectedCategory == value
              ? colorScheme.primary
              : colorScheme.surfaceContainerHighest,
          foregroundColor: selectedCategory == value
              ? colorScheme.onPrimary
              : colorScheme.onSurface,
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildBusinessesList(ColorScheme colorScheme) {
    final filteredBusinesses = _getFilteredBusinesses();

    if (filteredBusinesses.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(50),
          child: Column(
            children: [
              Icon(Icons.work_off,
                  size: 50, color: colorScheme.onSurfaceVariant),
              SizedBox(height: 10),
              Text(
                selectedCategory != "الكل"
                    ? 'لا توجد أعمال في هذه الفئة'
                    : 'لا توجد أعمال',
                style: TextStyle(
                  fontSize: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              if (!isOffline && selectedCategory == "الكل")
                Text(
                  'اضغط على زر "اضافة عمل" لإضافة أول عمل',
                  style: TextStyle(
                    fontSize: 14,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: filteredBusinesses.length,
      itemBuilder: (context, index) {
        var data = filteredBusinesses[index];
        return _buildBusinessCard(data, colorScheme);
      },
    );
  }

  Widget _buildBusinessCard(
    Map<String, dynamic> data,
    ColorScheme colorScheme,
  ) {
    Color statusColor = colorScheme.primary;
    String status = data['status'] ?? '';
    bool isSynced = data['synced'] == 1;

    if (status == 'مكتمل') {
      statusColor = Colors.green;
    } else if (status == 'ملغي') {
      statusColor = colorScheme.error;
    } else if (status == 'جاري التنفيذ') {
      statusColor = Colors.orange;
    }

    return Card(
      margin: EdgeInsets.all(10),
      color: !isSynced ? Colors.orange.withOpacity(0.05) : colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: !isSynced
            ? BorderSide(color: Colors.orange, width: 1)
            : BorderSide.none,
      ),
      child: Container(
        padding: EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!isSynced)
                      Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Tooltip(
                          message: 'غير متزامن - سيتم رفعه تلقائياً',
                          child: Icon(
                            Icons.sync_problem,
                            color: Colors.orange,
                            size: 20,
                          ),
                        ),
                      ),
                    IconButton(
                      onPressed: () {
                        // فتح نافذة التعديل
                        _openEditBusiness(data);
                      },
                      icon: Icon(Icons.edit, color: colorScheme.primary),
                      tooltip: 'تعديل العمل',
                    ),
                    IconButton(
                      onPressed: () => deleteBusiness(
                          data['id'], data['name'] ?? 'بدون اسم'),
                      icon: Icon(Icons.delete, color: colorScheme.error),
                      tooltip: 'حذف العمل',
                    ),
                  ],
                ),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    data['name'] ?? 'بدون اسم',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  data['description'] ?? '',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.right,
                ),
                if (data['customFields'] != null &&
                    (data['customFields'] as Map).isNotEmpty)
                  ..._buildCustomFieldsDisplay(
                      data['customFields'], colorScheme),
                Divider(color: colorScheme.outline),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDate(data['date']),
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "${data['amount'] ?? 0} ريال",
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildCustomFieldsDisplay(
    Map<String, dynamic> customFieldsData,
    ColorScheme colorScheme,
  ) {
    List<Widget> widgets = [];
    customFieldsData.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        widgets.add(
          Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _formatValue(value),
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.left,
                  ),
                ),
                Text(
                  key,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    });
    return widgets;
  }

  // ==================== نافذة إضافة/تعديل عمل ====================
  void _showAddEditBusinessBottomSheet(ColorScheme colorScheme) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateBottomSheet) {
            return Form(
              key: _formKey,
              child: Container(
                padding: EdgeInsets.all(15),
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.9,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        _isEditing ? "تعديل عمل" : "إضافة عمل",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (isOffline)
                        Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.info_outline,
                                    color: Colors.orange, size: 16),
                                SizedBox(width: 8),
                                Text(
                                  _isEditing
                                      ? 'سيتم تعديل العمل محلياً لعدم وجود اتصال'
                                      : 'سيتم حفظ العمل محلياً لعدم وجود اتصال',
                                  style: TextStyle(
                                      color: Colors.orange[700], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      SizedBox(height: 30),
                      _buildTextField(
                        "اسم العمل",
                        "ادخل اسم العمل",
                        (value) {
                          businessName = value;
                        },
                        initialValue: businessName,
                        validator: validateBusinessName,
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildTextField(
                        "وصف العمل",
                        "ادخل وصف العمل",
                        (value) {
                          businessDescription = value;
                        },
                        initialValue: businessDescription,
                        validator: validateBusinessDescription,
                        maxLines: 3,
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildTextField(
                        "المبلغ(ريال)",
                        "0.0",
                        (value) {
                          businessAmount = value;
                        },
                        initialValue: businessAmount,
                        keyboardType: TextInputType.number,
                        validator: validateBusinessAmount,
                        colorScheme: colorScheme,
                      ),
                      SizedBox(height: 20),
                      _buildDateField(date, colorScheme, setStateBottomSheet),
                      SizedBox(height: 20),
                      _buildStatusField(colorScheme),
                      if (customFieldsList.isNotEmpty) ...[
                        SizedBox(height: 30),
                        Divider(color: colorScheme.outline),
                        Center(
                          child: Text(
                            "حقول اضافية للتخصيص",
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(height: 20),
                        Column(
                          children: customFieldsList.map((field) {
                            return _buildCustomField(
                              field,
                              setStateBottomSheet,
                              colorScheme,
                            );
                          }).toList(),
                        ),
                      ],
                      SizedBox(height: 30),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton(
                            onPressed: () {
                              _resetEditingState();
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.error,
                            ),
                            child: Text(
                              "الغاء",
                              style: TextStyle(color: colorScheme.onError),
                            ),
                          ),
                          SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: () => _saveBusiness(context),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                            ),
                            child: Text(
                              _isEditing
                                  ? (isOffline ? "تعديل محلياً" : "تحديث")
                                  : (isOffline ? "حفظ محلياً" : "حفظ"),
                              style: TextStyle(color: colorScheme.onPrimary),
                            ),
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

  // دوال بناء واجهة المستخدم المعدلة لدعم القيم الأولية
  Widget _buildTextField(
    String label,
    String hint,
    Function(String) onChanged, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    required ColorScheme colorScheme,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              label,
              style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          maxLines: maxLines,
          textAlign: TextAlign.right,
          keyboardType: keyboardType,
          onChanged: (value) {
            onChanged(value);
          },
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            filled: true,
            hintText: hint,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            fillColor: colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.outline),
              borderRadius: BorderRadius.circular(10),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            errorBorder: OutlineInputBorder(
              borderSide: BorderSide(color: colorScheme.error),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(
    DateTime selectedDate,
    ColorScheme colorScheme,
    StateSetter setStateBottomSheet,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            "التاريخ",
            style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
          ),
        ),
        SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "${selectedDate.day}-${selectedDate.month}-${selectedDate.year}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                ),
                onPressed: () async {
                  DateTime? newDate = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime(1700),
                    lastDate: DateTime(2200),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(colorScheme: colorScheme),
                        child: child!,
                      );
                    },
                  );
                  if (newDate != null) {
                    setStateBottomSheet(() {
                      date = newDate;
                    });
                  }
                },
                child: Text(
                  "اختر التاريخ",
                  style: TextStyle(color: colorScheme.onPrimary),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatusField(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: EdgeInsets.all(10),
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              "الحالة",
              style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
            ),
          ),
        ),
        Directionality(
          textDirection: TextDirection.rtl,
          child: DropdownButtonFormField<String>(
            value: selectedStatus ?? "قيد الانتظار",
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary),
                borderRadius: BorderRadius.circular(10),
              ),
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
            ),
            icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
            iconSize: 30,
            dropdownColor: colorScheme.surface,
            isExpanded: true,
            items: statusItems.map((String item) {
              return DropdownMenuItem<String>(
                alignment: Alignment.centerRight,
                value: item,
                child: Text(
                  item,
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              setState(() {
                selectedStatus = newValue;
              });
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCustomField(
    Map<String, dynamic> field,
    StateSetter setStateBottomSheet,
    ColorScheme colorScheme,
  ) {
    String fieldName = field['fieldName'];
    String fieldType = field['fieldType'];
    bool isRequired = field['isRequired'] ?? false;

    switch (fieldType) {
      case 'نص':
        return _buildTextCustomField(fieldName, isRequired, colorScheme);
      case 'رقم':
        return _buildNumberCustomField(fieldName, isRequired, colorScheme);
      case 'تاريخ':
        return _buildDateCustomField(
          fieldName,
          isRequired,
          setStateBottomSheet,
          colorScheme,
        );
      case 'قائمة منسدلة':
        List<String> options = List<String>.from(field['options'] ?? []);
        return _buildDropdownCustomField(
          fieldName,
          options,
          isRequired,
          colorScheme,
        );
      default:
        return SizedBox.shrink();
    }
  }

  Widget _buildTextCustomField(
    String fieldName,
    bool isRequired,
    ColorScheme colorScheme,
  ) {
    // التأكد من وجود controller
    if (!textControllers.containsKey(fieldName)) {
      textControllers[fieldName] = TextEditingController();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text(
                  "مطلوب",
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              Flexible(
                child: Text(
                  fieldName,
                  style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: textControllers[fieldName],
            textAlign: TextAlign.right,
            style: TextStyle(color: colorScheme.onSurface),
            onChanged: (value) {
              customFieldsValues[fieldName] = value;
            },
            validator: isRequired
                ? (value) {
                    if (value == null || value.isEmpty) {
                      return 'هذا الحقل مطلوب';
                    }
                    return null;
                  }
                : null,
            decoration: InputDecoration(
              filled: true,
              hintText: "ادخل $fieldName",
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberCustomField(
    String fieldName,
    bool isRequired,
    ColorScheme colorScheme,
  ) {
    // التأكد من وجود controller
    if (!textControllers.containsKey(fieldName)) {
      textControllers[fieldName] = TextEditingController();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text(
                  "مطلوب",
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              Expanded(
                child: Text(
                  fieldName,
                  style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: textControllers[fieldName],
            textAlign: TextAlign.right,
            keyboardType: TextInputType.number,
            style: TextStyle(color: colorScheme.onSurface),
            onChanged: (value) {
              customFieldsValues[fieldName] = double.tryParse(value) ?? 0;
            },
            validator: isRequired
                ? (value) {
                    if (value == null || value.isEmpty) {
                      return 'هذا الحقل مطلوب';
                    }
                    if (double.tryParse(value) == null) {
                      return 'يرجى إدخال رقم صحيح';
                    }
                    return null;
                  }
                : null,
            decoration: InputDecoration(
              filled: true,
              hintText: "ادخل $fieldName",
              hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
              fillColor: colorScheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: colorScheme.outline),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.outline),
                borderRadius: BorderRadius.circular(10),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateCustomField(
    String fieldName,
    bool isRequired,
    StateSetter setStateBottomSheet,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text(
                  "مطلوب",
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              Expanded(
                child: Text(
                  fieldName,
                  style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "${dateValues[fieldName]?.day ?? DateTime.now().day}-${dateValues[fieldName]?.month ?? DateTime.now().month}-${dateValues[fieldName]?.year ?? DateTime.now().year}",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                  ),
                  onPressed: () async {
                    DateTime? newDate = await showDatePicker(
                      context: context,
                      initialDate: dateValues[fieldName] ?? DateTime.now(),
                      firstDate: DateTime(1700),
                      lastDate: DateTime(2200),
                      builder: (context, child) {
                        return Theme(
                          data: Theme.of(
                            context,
                          ).copyWith(colorScheme: colorScheme),
                          child: child!,
                        );
                      },
                    );
                    if (newDate != null) {
                      setStateBottomSheet(() {
                        dateValues[fieldName] = newDate;
                        customFieldsValues[fieldName] = newDate;
                      });
                    }
                  },
                  child: Text(
                    "اختر التاريخ",
                    style: TextStyle(color: colorScheme.onPrimary),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownCustomField(
    String fieldName,
    List<String> options,
    bool isRequired,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (isRequired)
                Text(
                  "مطلوب",
                  style: TextStyle(color: colorScheme.error, fontSize: 12),
                ),
              Expanded(
                child: Text(
                  fieldName,
                  style: TextStyle(fontSize: 17, color: colorScheme.onSurface),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          SizedBox(height: 8),
          Directionality(
            textDirection: TextDirection.rtl,
            child: DropdownButtonFormField<String>(
              value: dropdownValues[fieldName] ??
                  (options.isNotEmpty ? options[0] : null),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colorScheme.outline),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: colorScheme.primary),
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: colorScheme.surface,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              icon: Icon(Icons.arrow_drop_down, color: colorScheme.primary),
              iconSize: 30,
              dropdownColor: colorScheme.surface,
              isExpanded: true,
              items: options.map((String option) {
                return DropdownMenuItem<String>(
                  alignment: Alignment.centerRight,
                  value: option,
                  child: Text(
                    option,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      color: colorScheme.onSurface,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (String? newValue) {
                setState(() {
                  dropdownValues[fieldName] = newValue;
                  customFieldsValues[fieldName] = newValue;
                });
              },
              validator: isRequired
                  ? (value) {
                      if (value == null || value.isEmpty) {
                        return 'هذا الحقل مطلوب';
                      }
                      return null;
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
