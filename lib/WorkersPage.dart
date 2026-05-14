import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class WorkersPage extends StatefulWidget {
  final String userId;
  const WorkersPage({super.key, required this.userId});

  @override
  State<WorkersPage> createState() => _WorkersPageState();
}

class _WorkersPageState extends State<WorkersPage> {
  DateTime date = DateTime.now();
  final _formkey = GlobalKey<FormState>();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController specializationController =
      TextEditingController();
  final TextEditingController salaryController = TextEditingController();
  TextEditingController searchController = TextEditingController();

  bool isOffline = false;
  bool _isLoading = true;
  File? _workersFile;
  List<Map<String, dynamic>> _localWorkers = [];
  Timer? _syncTimer;

  String? _editingWorkerId;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _initStorage();
    _checkConnectivity();
    _startPeriodicSync();
  }

  // ==================== تهيئة التخزين في الملفات ====================
  Future<void> _initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String workersDirPath = path.join(appDir.path, 'workers_data');

      // إنشاء المجلد إذا لم يكن موجوداً
      final Directory workersDir = Directory(workersDirPath);
      if (!await workersDir.exists()) {
        await workersDir.create(recursive: true);
      }

      // مسار ملف العمال الخاص بالمستخدم
      final String filePath =
          path.join(workersDirPath, 'workers_${widget.userId}.json');
      _workersFile = File(filePath);

      await _loadLocalWorkers();
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

  // ==================== تحميل العمال من الملف ====================
  Future<void> _loadLocalWorkers() async {
    if (_workersFile == null) {
      return;
    }

    try {
      if (await _workersFile!.exists()) {
        final String jsonString = await _workersFile!.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _localWorkers = jsonList.cast<Map<String, dynamic>>();
      } else {
        _localWorkers = [];
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ خطأ في تحميل العمال من الملف: $e');
      _localWorkers = [];
    }
  }

  // ==================== حفظ العمال في الملف ====================
  Future<void> _saveWorkersToFile() async {
    if (_workersFile == null) {
      return;
    }

    try {
      final String jsonString = json.encode(_localWorkers);
      await _workersFile!.writeAsString(jsonString);
    } catch (e) {
      print('❌ خطأ في حفظ العمال في الملف: $e');
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
    if (_workersFile == null) return;

    final bool hasInternet = await _hasInternet();
    if (!hasInternet) return;

    try {
      // 1. رفع العمال غير المتزامنين إلى السحاب
      final List<Map<String, dynamic>> unsyncedWorkers =
          _localWorkers.where((worker) => worker['synced'] == 0).toList();

      for (var worker in unsyncedWorkers) {
        try {
          final docRef = firestore
              .collection('users')
              .doc(widget.userId)
              .collection('workers')
              .doc(worker['id']);

          final docSnapshot = await docRef.get();

          if (!docSnapshot.exists) {
            await docRef.set({
              'name': worker['name'],
              'phone': worker['phone'],
              'specialization': worker['specialization'],
              'salary': worker['salary'],
              'date': Timestamp.fromDate(DateTime.parse(worker['date'])),
              'createdAt': worker['createdAt'],
            });
          } else {
            // تحديث العامل الموجود
            await docRef.update({
              'name': worker['name'],
              'phone': worker['phone'],
              'specialization': worker['specialization'],
              'salary': worker['salary'],
              'date': Timestamp.fromDate(DateTime.parse(worker['date'])),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          // تحديث حالة المزامنة في القائمة المحلية
          final index =
              _localWorkers.indexWhere((e) => e['id'] == worker['id']);
          if (index != -1) {
            _localWorkers[index]['synced'] = 1;
          }
        } catch (e) {
          print('❌ خطأ في رفع العامل ${worker['id']}: $e');
        }
      }

      // حفظ التغييرات المحلية بعد رفع العمال
      if (unsyncedWorkers.isNotEmpty) {
        await _saveWorkersToFile();
      }

      // 2. تحميل العمال الجدد من السحاب
      final lastSyncTime = await _getLastSyncTime();

      final QuerySnapshot cloudWorkers = await firestore
          .collection('users')
          .doc(widget.userId)
          .collection('workers')
          .where('createdAt', isGreaterThan: lastSyncTime)
          .get();

      int addedCount = 0;
      for (var doc in cloudWorkers.docs) {
        final workerData = doc.data() as Map<String, dynamic>;
        final workerId = doc.id;

        final existingWorker = _localWorkers.any((e) => e['id'] == workerId);

        if (!existingWorker) {
          final newWorker = {
            'id': workerId,
            'name': workerData['name'],
            'phone': workerData['phone'],
            'specialization': workerData['specialization'],
            'salary': workerData['salary'],
            'date':
                (workerData['date'] as Timestamp).toDate().toIso8601String(),
            'synced': 1,
            'createdAt':
                workerData['createdAt'] ?? DateTime.now().toIso8601String(),
          };
          _localWorkers.add(newWorker);
          addedCount++;
        }
      }

      // ترتيب العمال حسب التاريخ
      _localWorkers.sort((a, b) => b['date'].compareTo(a['date']));

      if (addedCount > 0) {
        await _saveWorkersToFile();
      }

      await _saveLastSyncTime(DateTime.now().toIso8601String());
      await _loadLocalWorkers();

      if (mounted && (unsyncedWorkers.isNotEmpty || addedCount > 0)) {
        String message = '';
        if (unsyncedWorkers.isNotEmpty)
          message += 'تم رفع ${unsyncedWorkers.length} عامل';
        if (addedCount > 0) {
          if (message.isNotEmpty) message += ' و ';
          message += 'تم تحميل $addedCount عامل جديد';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(' $message'),
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
    return prefs.getString('last_sync_workers_${widget.userId}') ??
        '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_workers_${widget.userId}', time);
  }

  // ==================== دوال التحقق ====================
  String? validateName(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال اسم العامل';
    if (value.length < 3) return 'الاسم يجب أن يكون على الأقل 3 أحرف';
    return null;
  }

  String? validatePhone(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال رقم الهاتف';
    if (!RegExp(r'^\d{9}$').hasMatch(value))
      return 'الرجاء إدخال رقم هاتف صالح (9 أرقام)';
    return null;
  }

  String? validateSpecialization(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال تخصص العامل';
    if (value.length < 3) return 'التخصص يجب أن يكون على الأقل 3 أحرف';
    return null;
  }

  String? validateSalary(String? value) {
    if (value == null || value.isEmpty) return 'الرجاء إدخال راتب العامل';
    if (double.tryParse(value) == null) return 'الرجاء إدخال رقم صالح للراتب';
    return null;
  }

  // ==================== فتح نافذة التعديل ====================
  void _openEditWorker(Map<String, dynamic> worker) {
    // تعبئة الحقول بالبيانات الحالية
    nameController.text = worker['name'] ?? '';
    phoneController.text = worker['phone'] ?? '';
    specializationController.text = worker['specialization'] ?? '';
    salaryController.text = worker['salary']?.toString() ?? '';

    try {
      date = DateTime.parse(worker['date']);
    } catch (e) {
      date = DateTime.now();
    }

    _editingWorkerId = worker['id'];
    _isEditing = true;

    // فتح نافذة الإضافة/التعديل
    _showAddEditWorkerBottomSheet(Theme.of(context).colorScheme);
  }

  // ==================== إعادة تعيين حالة التعديل ====================
  void _resetEditingState() {
    _editingWorkerId = null;
    _isEditing = false;
    clearForm();
  }

  // ==================== حفظ أو تحديث العامل ====================
  Future<void> saveWorker() async {
    if (_formkey.currentState!.validate()) {
      String name = nameController.text;
      String phone = phoneController.text;
      String specialization = specializationController.text;
      String salary = salaryController.text;
      DateTime workerDate = date;

      final workerId = _isEditing && _editingWorkerId != null
          ? _editingWorkerId!
          : DateTime.now().millisecondsSinceEpoch.toString();
      final createdAt = _isEditing
          ? _localWorkers.firstWhere((e) => e['id'] == workerId)['createdAt']
          : DateTime.now().toIso8601String();

      Map<String, dynamic> workerData = {
        "id": workerId,
        "name": name,
        "phone": phone,
        "specialization": specialization,
        "salary": salary,
        "date": workerDate.toIso8601String(),
        "synced": 0,
        "createdAt": createdAt,
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
          // تعديل العامل الموجود
          final index = _localWorkers.indexWhere((e) => e['id'] == workerId);
          if (index != -1) {
            _localWorkers[index] = workerData;
          }
        } else {
          // إضافة عامل جديد
          _localWorkers.insert(0, workerData);
        }

        // ترتيب العمال حسب التاريخ
        _localWorkers.sort((a, b) => b['date'].compareTo(a['date']));
        await _saveWorkersToFile();
        await _loadLocalWorkers();

        final bool hasInternet = await _hasInternet();

        if (hasInternet) {
          try {
            if (_isEditing) {
              // تحديث في السحاب
              await firestore
                  .collection('users')
                  .doc(widget.userId)
                  .collection('workers')
                  .doc(workerId)
                  .update({
                'name': name,
                'phone': phone,
                'specialization': specialization,
                'salary': salary,
                'date': Timestamp.fromDate(workerDate),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } else {
              // إضافة جديدة في السحاب
              await firestore
                  .collection('users')
                  .doc(widget.userId)
                  .collection('workers')
                  .doc(workerId)
                  .set({
                'name': name,
                'phone': phone,
                'specialization': specialization,
                'salary': salary,
                'date': Timestamp.fromDate(workerDate),
                'createdAt': createdAt,
              });
            }

            // تحديث حالة المزامنة
            final index = _localWorkers.indexWhere((e) => e['id'] == workerId);
            if (index != -1) {
              _localWorkers[index]['synced'] = 1;
              await _saveWorkersToFile();
              await _loadLocalWorkers();
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
                    ? 'تم تعديل بيانات العامل بنجاح (محلياً وسحابياً)'
                    : 'تم حفظ بيانات العامل بنجاح (محلياً وسحابياً)',
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
                  'لا يوجد اتصال بالإنترنت. تم ${_isEditing ? 'تعديل' : 'حفظ'} العامل محلياً وسيتم مزامنته تلقائياً',
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
    } else {
      if (mounted) {
        AwesomeDialog(
          context: context,
          dialogType: DialogType.error,
          animType: AnimType.bottomSlide,
          title: 'خطأ',
          desc: 'يرجى تصحيح الأخطاء في النموذج قبل الحفظ',
          btnOkText: 'حسناً',
        ).show();
      }
    }
  }

  void clearForm() {
    nameController.clear();
    phoneController.clear();
    specializationController.clear();
    salaryController.clear();
    date = DateTime.now();
  }

  // ==================== حذف العامل ====================
  Future<void> deleteWorker(String workerId, String workerName) async {
    if (!mounted) return;

    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد من حذف العامل "$workerName"؟',
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
          // حذف العامل من القائمة المحلية
          _localWorkers.removeWhere((worker) => worker['id'] == workerId);
          await _saveWorkersToFile();
          await _loadLocalWorkers();

          final bool hasInternet = await _hasInternet();
          if (hasInternet) {
            await firestore
                .collection('users')
                .doc(widget.userId)
                .collection('workers')
                .doc(workerId)
                .delete();
          }

          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(" تم حذف العامل بنجاح"),
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
                content: Text(" حدث خطأ أثناء حذف العامل: $e"),
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

  // ==================== فلترة العمال ====================
  List<Map<String, dynamic>> getFilteredWorkers() {
    return _localWorkers.where((worker) {
      final workerName = worker['name']?.toString().toLowerCase() ?? '';
      final searchText = searchController.text.toLowerCase();
      return searchText.isEmpty || workerName.contains(searchText);
    }).toList();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    nameController.dispose();
    phoneController.dispose();
    specializationController.dispose();
    salaryController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredWorkers = getFilteredWorkers();

    // عرض مؤشر تحميل أثناء تحميل البيانات
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
              Text('جاري تحميل العمال...',
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
            onPressed: () async {
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
            icon: Icon(Icons.sync, color: colorScheme.primary),
            tooltip: 'مزامنة مع السحاب',
          ),
          if (isOffline)
            Padding(
              padding: EdgeInsets.all(8),
              child: Tooltip(
                message: 'وضع غير متصل - سيتم حفظ البيانات محلياً',
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
      body: Column(
        children: [
          // إشعار وضع عدم الاتصال
          if (isOffline)
            Container(
              margin: EdgeInsets.all(10),
              padding: EdgeInsets.all(12),
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
                      'وضع غير متصل - سيتم حفظ العمال محلياً ومزامنتهم تلقائياً عند عودة الاتصال',
                      style: TextStyle(color: Colors.orange[700], fontSize: 12),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),

          Container(
            padding: const EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _resetEditingState();
                    _showAddEditWorkerBottomSheet(colorScheme);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text("اضافة عامل"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                  ),
                ),
                Text(
                  "العمال",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // شريط البحث
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextFormField(
              controller: searchController,
              textAlign: TextAlign.right,
              onChanged: (value) {
                setState(() {});
              },
              style: TextStyle(color: colorScheme.onSurface),
              decoration: InputDecoration(
                suffixIcon: Icon(Icons.search, color: colorScheme.primary),
                hintText: "البحث باسم العامل",
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
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),

          // معلومات العدد وحالة المزامنة
          if (_localWorkers.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إجمالي العمال: ${filteredWorkers.length}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (_localWorkers.any((e) => e['synced'] == 0))
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⚠️ يوجد عمال غير متزامنين',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),

          // قائمة العمال
          Expanded(
            child: filteredWorkers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.people,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: 16),
                        Text(
                          searchController.text.isNotEmpty
                              ? 'لا توجد نتائج للبحث عن "${searchController.text}"'
                              : 'لا يوجد عمال\nاضغط على زر "اضافة عامل" لإضافة أول عامل',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: filteredWorkers.length,
                    itemBuilder: (context, index) {
                      final worker = filteredWorkers[index];
                      return _buildWorkerCard(worker, colorScheme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== بطاقة عرض العامل ====================
  Widget _buildWorkerCard(
      Map<String, dynamic> worker, ColorScheme colorScheme) {
    String name = worker['name'] ?? 'بدون اسم';
    String phone = worker['phone'] ?? 'بدون رقم';
    String specialization = worker['specialization'] ?? 'بدون تخصص';
    String salary = worker['salary']?.toString() ?? '0';
    String workerId = worker['id'];
    bool isSynced = worker['synced'] == 1;
    String displayDate = '';

    try {
      DateTime workerDate = DateTime.parse(worker['date']);
      displayDate = '${workerDate.year}-${workerDate.month}-${workerDate.day}';
    } catch (e) {
      displayDate = 'تاريخ غير محدد';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Container(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (!isSynced)
                      Container(
                        margin: EdgeInsets.only(left: 8),
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.sync_problem,
                          color: Colors.orange,
                          size: 16,
                        ),
                      ),
                    IconButton(
                      onPressed: () {
                        // فتح نافذة التعديل
                        _openEditWorker(worker);
                      },
                      icon: Icon(Icons.edit, color: colorScheme.primary),
                      tooltip: 'تعديل العامل',
                    ),
                    IconButton(
                      onPressed: () => deleteWorker(workerId, name),
                      icon: Icon(Icons.delete, color: colorScheme.error),
                      tooltip: 'حذف العامل',
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.person, color: colorScheme.primary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 15),
            Divider(color: colorScheme.outline),
            const SizedBox(height: 10),
            _buildInfoRow(
              Icons.phone,
              phone,
              color: colorScheme.primary,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildInfoRow(
              Icons.attach_money,
              "$salary ريال/شهر",
              color: Colors.green,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildInfoRow(
              Icons.hotel_class,
              specialization,
              color: Colors.deepOrange,
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 10),
            _buildInfoRow(
              Icons.punch_clock,
              displayDate,
              color: Colors.indigo,
              colorScheme: colorScheme,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== نافذة إضافة/تعديل عامل ====================
  void _showAddEditWorkerBottomSheet(ColorScheme colorScheme) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateBottomSheet) {
            return Form(
              key: _formkey,
              child: Container(
                padding: const EdgeInsets.all(15),
                width: double.infinity,
                height: 600,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Text(
                        _isEditing ? "تعديل عامل" : "إضافة عامل",
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
                                      ? 'سيتم تعديل العامل محلياً لعدم وجود اتصال'
                                      : 'سيتم حفظ العامل محلياً لعدم وجود اتصال',
                                  style: TextStyle(
                                      color: Colors.orange[700], fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 30),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("اسم العامل",
                            style: TextStyle(
                                fontSize: 17, color: colorScheme.onSurface)),
                      ),
                      TextFormField(
                        controller: nameController,
                        validator: validateName,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: _buildInputDecoration(
                            "ادخل اسم العامل", colorScheme),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("رقم الهاتف",
                            style: TextStyle(
                                fontSize: 17, color: colorScheme.onSurface)),
                      ),
                      TextFormField(
                        controller: phoneController,
                        validator: validatePhone,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: _buildInputDecoration(
                            "ادخل رقم الهاتف", colorScheme),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("التخصص",
                            style: TextStyle(
                                fontSize: 17, color: colorScheme.onSurface)),
                      ),
                      TextFormField(
                        controller: specializationController,
                        validator: validateSpecialization,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textAlign: TextAlign.right,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: _buildInputDecoration(
                            "مثال: كهربائي أو سباك", colorScheme),
                      ),
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("الراتب",
                            style: TextStyle(
                                fontSize: 17, color: colorScheme.onSurface)),
                      ),
                      TextFormField(
                        controller: salaryController,
                        validator: validateSalary,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textAlign: TextAlign.right,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: _buildInputDecoration("0.0", colorScheme),
                      ),
                      SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text("التاريخ",
                            style: TextStyle(
                                fontSize: 17, color: colorScheme.onSurface)),
                      ),
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
                              "${date.day}-${date.month}-${date.year}",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary),
                              onPressed: () async {
                                DateTime? newDate = await showDatePicker(
                                  context: context,
                                  initialDate: date,
                                  firstDate: DateTime(1700),
                                  lastDate: DateTime(2200),
                                  builder: (context, child) {
                                    return Theme(
                                      data: Theme.of(context)
                                          .copyWith(colorScheme: colorScheme),
                                      child: child!,
                                    );
                                  },
                                );
                                if (newDate == null) return;
                                setStateBottomSheet(() {
                                  date = newDate;
                                });
                              },
                              child: Text("اختر التاريخ",
                                  style:
                                      TextStyle(color: colorScheme.onPrimary)),
                            ),
                          ],
                        ),
                      ),
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
                                backgroundColor: colorScheme.error),
                            child: Text("الغاء",
                                style: TextStyle(color: colorScheme.onError)),
                          ),
                          const SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: saveWorker,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: colorScheme.primary),
                            child: Row(
                              children: [
                                if (isOffline) Icon(Icons.save, size: 18),
                                if (isOffline) SizedBox(width: 8),
                                Text(
                                  _isEditing
                                      ? (isOffline ? "تعديل محلياً" : "تحديث")
                                      : (isOffline ? "حفظ محلياً" : "حفظ"),
                                ),
                              ],
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

  // ==================== دوال مساعدة ====================
  InputDecoration _buildInputDecoration(
      String hintText, ColorScheme colorScheme) {
    return InputDecoration(
      filled: true,
      hintText: hintText,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      fillColor: colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text,
      {Color? color, required ColorScheme colorScheme}) {
    return Align(
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(
              color: color ?? colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          Icon(icon, color: color ?? colorScheme.primary),
        ],
      ),
    );
  }
}
