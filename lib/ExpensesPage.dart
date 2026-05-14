import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class ExpensesPage extends StatefulWidget {
  final String userId;
  const ExpensesPage({super.key, required this.userId});

  @override
  State<ExpensesPage> createState() => _ExpensesPageState();
}

class _ExpensesPageState extends State<ExpensesPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController searchController = TextEditingController();
  DateTime date = DateTime.now();
  String selectedCategory = "الكل";
  String? selectedValue;
  List<String> items = [
    'ادوات ومعدات',
    'مواد ومستلزمات',
    'نقل ومواصلات',
    'اكل ومشروبات',
    'اخرى',
  ];

  bool isOffline = false;
  bool _isLoading = true;
  File? _expensesFile;
  List<Map<String, dynamic>> _localExpenses = [];
  Timer? _syncTimer;

  // متغيرات خاصة بالتعديل
  String? _editingExpenseId;
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
      final String expensesDirPath = path.join(appDir.path, 'expenses_data');

      final Directory expensesDir = Directory(expensesDirPath);
      if (!await expensesDir.exists()) {
        await expensesDir.create(recursive: true);
      }

      final String filePath =
          path.join(expensesDirPath, 'expenses_${widget.userId}.json');
      _expensesFile = File(filePath);

      await _loadLocalExpenses();
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

  // ==================== تحميل المصروفات من الملف ====================
  Future<void> _loadLocalExpenses() async {
    if (_expensesFile == null) {
      return;
    }

    try {
      if (await _expensesFile!.exists()) {
        final String jsonString = await _expensesFile!.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _localExpenses = jsonList.cast<Map<String, dynamic>>();
      } else {
        _localExpenses = [];
      }
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('❌ خطأ في تحميل المصروفات من الملف: $e');
      _localExpenses = [];
    }
  }

  // ==================== حفظ المصروفات في الملف ====================
  Future<void> _saveExpensesToFile() async {
    if (_expensesFile == null) {
      return;
    }

    try {
      final String jsonString = json.encode(_localExpenses);
      await _expensesFile!.writeAsString(jsonString);
    } catch (e) {
      print('❌ خطأ في حفظ المصروفات في الملف: $e');
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
    if (_expensesFile == null) return;

    final bool hasInternet = await _hasInternet();
    if (!hasInternet) return;

    try {
      final List<Map<String, dynamic>> unsyncedExpenses =
          _localExpenses.where((expense) => expense['synced'] == 0).toList();

      for (var expense in unsyncedExpenses) {
        try {
          final docRef = firestore
              .collection('users')
              .doc(widget.userId)
              .collection('expenses')
              .doc(expense['id']);

          final docSnapshot = await docRef.get();

          if (!docSnapshot.exists) {
            await docRef.set({
              'description': expense['description'],
              'amount': expense['amount'],
              'category': expense['category'],
              'date': Timestamp.fromDate(DateTime.parse(expense['date'])),
              'createdAt': expense['createdAt'],
            });
          } else {
            // تحديث المصروف الموجود
            await docRef.update({
              'description': expense['description'],
              'amount': expense['amount'],
              'category': expense['category'],
              'date': Timestamp.fromDate(DateTime.parse(expense['date'])),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }

          final index =
              _localExpenses.indexWhere((e) => e['id'] == expense['id']);
          if (index != -1) {
            _localExpenses[index]['synced'] = 1;
          }
        } catch (e) {
          print('❌ خطأ في رفع المصروف ${expense['id']}: $e');
        }
      }

      if (unsyncedExpenses.isNotEmpty) {
        await _saveExpensesToFile();
      }

      final lastSyncTime = await _getLastSyncTime();

      final QuerySnapshot cloudExpenses = await firestore
          .collection('users')
          .doc(widget.userId)
          .collection('expenses')
          .where('createdAt', isGreaterThan: lastSyncTime)
          .get();

      int addedCount = 0;
      for (var doc in cloudExpenses.docs) {
        final expenseData = doc.data() as Map<String, dynamic>;
        final expenseId = doc.id;

        final existingExpense = _localExpenses.any((e) => e['id'] == expenseId);

        if (!existingExpense) {
          final newExpense = {
            'id': expenseId,
            'description': expenseData['description'],
            'amount': expenseData['amount'],
            'category': expenseData['category'],
            'date':
                (expenseData['date'] as Timestamp).toDate().toIso8601String(),
            'synced': 1,
            'createdAt':
                expenseData['createdAt'] ?? DateTime.now().toIso8601String(),
          };
          _localExpenses.add(newExpense);
          addedCount++;
        }
      }

      _localExpenses.sort((a, b) => b['date'].compareTo(a['date']));

      if (addedCount > 0) {
        await _saveExpensesToFile();
      }

      await _saveLastSyncTime(DateTime.now().toIso8601String());
      await _loadLocalExpenses();

      if (mounted && (unsyncedExpenses.isNotEmpty || addedCount > 0)) {
        String message = '';
        if (unsyncedExpenses.isNotEmpty)
          message += 'تم رفع ${unsyncedExpenses.length} مصروف';
        if (addedCount > 0) {
          if (message.isNotEmpty) message += ' و ';
          message += 'تم تحميل $addedCount مصروف جديد';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message'),
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
    return prefs.getString('last_sync_${widget.userId}') ?? '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_${widget.userId}', time);
  }

  // ==================== فتح نافذة التعديل ====================
  void _openEditExpense(Map<String, dynamic> expense) {
    descriptionController.text = expense['description'] ?? '';
    amountController.text = expense['amount']?.toString() ?? '';
    selectedValue = expense['category'] ?? 'اخرى';

    try {
      date = DateTime.parse(expense['date']);
    } catch (e) {
      date = DateTime.now();
    }

    _editingExpenseId = expense['id'];
    _isEditing = true;

    // فتح نافذة الإضافة/التعديل
    _showAddEditExpenseBottomSheet(Theme.of(context).colorScheme);
  }

  // ==================== إعادة تعيين حالة التعديل ====================
  void _resetEditingState() {
    _editingExpenseId = null;
    _isEditing = false;
    clearForm();
  }

  // ==================== حفظ أو تحديث المصروف ====================
  Future<void> saveExpense() async {
    if (_formKey.currentState!.validate()) {
      String description = descriptionController.text;
      double amount = double.parse(amountController.text);
      String category = selectedValue ?? "اخرى";
      DateTime expenseDate = date;

      final expenseId = _isEditing && _editingExpenseId != null
          ? _editingExpenseId!
          : DateTime.now().millisecondsSinceEpoch.toString();
      final createdAt = _isEditing
          ? _localExpenses.firstWhere((e) => e['id'] == expenseId)['createdAt']
          : DateTime.now().toIso8601String();

      Map<String, dynamic> expenseData = {
        "id": expenseId,
        "description": description,
        "amount": amount,
        "category": category,
        "date": expenseDate.toIso8601String(),
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
          // تعديل المصروف الموجود
          final index = _localExpenses.indexWhere((e) => e['id'] == expenseId);
          if (index != -1) {
            _localExpenses[index] = expenseData;
          }
        } else {
          // إضافة مصروف جديد
          _localExpenses.insert(0, expenseData);
        }

        // ترتيب المصروفات حسب التاريخ
        _localExpenses.sort((a, b) => b['date'].compareTo(a['date']));
        await _saveExpensesToFile();
        await _loadLocalExpenses();

        final bool hasInternet = await _hasInternet();

        if (hasInternet) {
          try {
            if (_isEditing) {
              // تحديث في السحاب
              await firestore
                  .collection('users')
                  .doc(widget.userId)
                  .collection('expenses')
                  .doc(expenseId)
                  .update({
                'description': description,
                'amount': amount,
                'category': category,
                'date': Timestamp.fromDate(expenseDate),
                'updatedAt': FieldValue.serverTimestamp(),
              });
            } else {
              // إضافة جديدة في السحاب
              await firestore
                  .collection('users')
                  .doc(widget.userId)
                  .collection('expenses')
                  .doc(expenseId)
                  .set({
                'description': description,
                'amount': amount,
                'category': category,
                'date': Timestamp.fromDate(expenseDate),
                'createdAt': createdAt,
              });
            }

            // تحديث حالة المزامنة
            final index =
                _localExpenses.indexWhere((e) => e['id'] == expenseId);
            if (index != -1) {
              _localExpenses[index]['synced'] = 1;
              await _saveExpensesToFile();
              await _loadLocalExpenses();
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
                    ? 'تم تعديل بيانات المصروف بنجاح (محلياً وسحابياً)'
                    : 'تم حفظ بيانات المصروف بنجاح (محلياً وسحابياً)',
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
                  'لا يوجد اتصال بالإنترنت. تم ${_isEditing ? 'تعديل' : 'حفظ'} المصروف محلياً',
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
    descriptionController.clear();
    amountController.clear();
    selectedValue = null;
    date = DateTime.now();
  }

  // ==================== حذف المصروف ====================
  Future<void> deleteExpense(String expenseId, String description) async {
    if (!mounted) return;

    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل أنت متأكد أنك تريد حذف المصروف "$description"؟',
      btnCancelText: 'إلغاء',
      btnOkText: 'حذف',
      btnCancelOnPress: () {},
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
          // حذف المصروف من القائمة المحلية
          _localExpenses.removeWhere((expense) => expense['id'] == expenseId);
          await _saveExpensesToFile();
          await _loadLocalExpenses();

          final bool hasInternet = await _hasInternet();
          if (hasInternet) {
            await firestore
                .collection('users')
                .doc(widget.userId)
                .collection("expenses")
                .doc(expenseId)
                .delete();
          }

          if (mounted) Navigator.of(context).pop();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(" تم حذف المصروف بنجاح"),
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
                content: Text(" حدث خطأ أثناء حذف المصروف: $e"),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      },
    ).show();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    descriptionController.dispose();
    amountController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ==================== فلترة المصروفات ====================
  List<Map<String, dynamic>> getFilteredExpenses() {
    return _localExpenses.where((expense) {
      final expenseName =
          expense['description']?.toString().toLowerCase() ?? '';
      final searchText = searchController.text.toLowerCase();
      final matchesSearch =
          searchText.isEmpty || expenseName.contains(searchText);
      final matchesCategory =
          selectedCategory == "الكل" || expense['category'] == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
  }

  // ==================== واجهة المستخدم ====================
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filteredExpenses = getFilteredExpenses();

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
              Text('جاري تحميل المصروفات...',
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
                message: 'وضع غير متصل - سيتم حفظ المصروفات محلياً',
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
          Container(
            padding: EdgeInsets.all(10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _resetEditingState();
                    _showAddEditExpenseBottomSheet(colorScheme);
                  },
                  label: Text(
                    "إضافة مصروف",
                    style: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  icon: Icon(Icons.add, color: colorScheme.onPrimary),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                  ),
                ),
                Text(
                  "المصروفات",
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
                      'وضع غير متصل. سيتم حفظ المصروفات الجديدة محلياً ومزامنتها تلقائياً عند عودة الاتصال.',
                      style: TextStyle(color: Colors.orange[700], fontSize: 12),
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
              cursorColor: colorScheme.primary,
              textAlign: TextAlign.right,
              controller: searchController,
              style: TextStyle(color: colorScheme.onSurface),
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                suffixIcon: Icon(Icons.search, color: colorScheme.primary),
                hintText: "البحث عن مصروف",
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
          SizedBox(height: 10),
          _buildFilterButtons(colorScheme),
          if (_localExpenses.isNotEmpty)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'إجمالي المصروفات: ${filteredExpenses.length}',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  if (_localExpenses.any((e) => e['synced'] == 0))
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '⚠️ يوجد مصروفات غير متزامنة',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 11,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: filteredExpenses.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.receipt_long,
                          size: 64,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        SizedBox(height: 16),
                        Text(
                          searchController.text.isNotEmpty
                              ? 'لا توجد نتائج للبحث عن "${searchController.text}"'
                              : 'لا يوجد مصروفات\nاضغط على زر "إضافة مصروف" لإضافة أول مصروف',
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
                    itemCount: filteredExpenses.length,
                    itemBuilder: (BuildContext context, int index) {
                      final expense = filteredExpenses[index];
                      return _buildExpenseCard(expense, colorScheme);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== بطاقة عرض المصروف ====================
  Widget _buildExpenseCard(
      Map<String, dynamic> expense, ColorScheme colorScheme) {
    String amount = expense['amount']?.toString() ?? '0';
    String category = expense['category'] ?? 'غير محدد';
    String description = expense['description'] ?? 'بدون وصف';
    String expenseId = expense['id'];
    bool isSynced = expense['synced'] == 1;
    String displayDate = '';

    try {
      DateTime expenseDate = DateTime.parse(expense['date']);
      displayDate =
          '${expenseDate.year}-${expenseDate.month}-${expenseDate.day}';
    } catch (e) {
      displayDate = 'تاريخ غير محدد';
    }

    Color categoryColor = Colors.green;
    if (category == 'ادوات ومعدات')
      categoryColor = Colors.blue;
    else if (category == 'نقل ومواصلات')
      categoryColor = Colors.orange;
    else if (category == 'اكل ومشروبات')
      categoryColor = Colors.deepOrange;
    else if (category == 'اخرى') categoryColor = Colors.purple;

    return Card(
      margin: EdgeInsets.all(10),
      color: colorScheme.surface,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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
                        _openEditExpense(expense);
                      },
                      icon: Icon(Icons.edit, color: colorScheme.primary),
                      tooltip: 'تعديل المصروف',
                    ),
                    IconButton(
                      onPressed: () => deleteExpense(expenseId, description),
                      icon: Icon(Icons.delete, color: colorScheme.error),
                      tooltip: 'حذف المصروف',
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      description,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 5),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: categoryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        category,
                        style: TextStyle(
                          color: categoryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      "-$amount ريال",
                      style: TextStyle(
                        color: colorScheme.error,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      displayDate,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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

  // ==================== نافذة إضافة/تعديل مصروف ====================
  void _showAddEditExpenseBottomSheet(ColorScheme colorScheme) {
    showModalBottomSheet(
      showDragHandle: true,
      isScrollControlled: true,
      context: context,
      backgroundColor: colorScheme.surface,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setStateBottomSheet) {
            return Container(
              padding: EdgeInsets.all(15),
              width: double.infinity,
              height: 600,
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      Text(
                        _isEditing ? "تعديل مصروف" : "إضافة مصروف",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 30),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "وصف المصروف",
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: 17,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      TextFormField(
                        controller: descriptionController,
                        textAlign: TextAlign.right,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return "الرجاء ادخال وصف المصروف";
                          }
                          return null;
                        },
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: _buildInputDecoration(
                          "ادخل وصف المصروف",
                          colorScheme,
                        ),
                      ),
                      SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "المبلغ(ريال)",
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: 17,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      TextFormField(
                        controller: amountController,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        textAlign: TextAlign.right,
                        validator: (value) {
                          if (value?.isEmpty ?? true) {
                            return "الرجاء ادخال مبلغ المصروف";
                          }
                          try {
                            double amount = double.parse(value!);
                            if (amount <= 0) {
                              return "الرجاء ادخال مبلغ صحيح";
                            }
                          } catch (e) {
                            return "الرجاء ادخال مبلغ صحيح";
                          }
                          return null;
                        },
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: colorScheme.onSurface),
                        decoration: _buildInputDecoration("0.0", colorScheme),
                      ),
                      SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "الفئة",
                          textAlign: TextAlign.start,
                          style: TextStyle(
                            fontSize: 17,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      Directionality(
                        textDirection: TextDirection.rtl,
                        child: DropdownButtonFormField<String>(
                          value: selectedValue ?? "اخرى",
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: colorScheme.outline,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                color: colorScheme.primary,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            filled: true,
                            fillColor: colorScheme.surface,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          icon: Icon(
                            Icons.arrow_drop_down,
                            color: colorScheme.primary,
                          ),
                          iconSize: 30,
                          dropdownColor: colorScheme.surface,
                          isExpanded: true,
                          items: items.map((String item) {
                            return DropdownMenuItem<String>(
                              alignment: Alignment.centerRight,
                              value: item,
                              child: Text(
                                item,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            setStateBottomSheet(() {
                              selectedValue = newValue;
                            });
                          },
                        ),
                      ),
                      SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "التاريخ",
                          style: TextStyle(
                            fontSize: 17,
                            color: colorScheme.onSurface,
                          ),
                        ),
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
                                  initialDate: date,
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
                                if (newDate == null) return;
                                setStateBottomSheet(() {
                                  date = newDate;
                                });
                              },
                              child: Text(
                                "اختر التاريخ",
                                style: TextStyle(color: colorScheme.onPrimary),
                              ),
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
                              backgroundColor: colorScheme.error,
                            ),
                            child: Text(
                              "الغاء",
                              style: TextStyle(color: colorScheme.onError),
                            ),
                          ),
                          SizedBox(width: 15),
                          ElevatedButton(
                            onPressed: saveExpense,
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

  // ==================== دوال مساعدة ====================
  InputDecoration _buildInputDecoration(
    String hintText,
    ColorScheme colorScheme,
  ) {
    return InputDecoration(
      filled: true,
      hintText: hintText,
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
    );
  }

  Widget _buildFilterButtons(ColorScheme colorScheme) {
    List<Map<String, String>> filters = [
      {'label': 'الكل', 'value': 'الكل'},
      {'label': 'ادوات ومعدات', 'value': 'ادوات ومعدات'},
      {'label': 'مواد ومستلزمات', 'value': 'مواد ومستلزمات'},
      {'label': 'نقل ومواصلات', 'value': 'نقل ومواصلات'},
      {'label': 'اكل ومشروبات', 'value': 'اكل ومشروبات'},
      {'label': 'اخرى', 'value': 'اخرى'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: filters.map((filter) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: ElevatedButton(
              onPressed: () {
                setState(() {
                  selectedCategory = filter['value']!;
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedCategory == filter['value']
                    ? colorScheme.primary
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: selectedCategory == filter['value']
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
              child: Text(filter['label']!),
            ),
          );
        }).toList(),
      ),
    );
  }
}
