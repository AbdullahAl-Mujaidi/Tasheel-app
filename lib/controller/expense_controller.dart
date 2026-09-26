// ignore_for_file: avoid_print
import 'dart:async';
import 'package:fkra/admin/services/admin_session_service.dart';
import 'package:fkra/model/expense_model.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/activity_service.dart';
import 'package:fkra/services/analytics_service.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:flutter/material.dart';

class ExpenseController extends ChangeNotifier {
  final String userId;
  final ExpenseModel _model;

  // الحالة الأساسية
  List<Map<String, dynamic>> expenses = [];
  bool isOffline = false;
  bool isLoading = true;
  String selectedCategory = "الكل";

  // متغيرات النموذج (الحقول)
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController descriptionController = TextEditingController();
  final TextEditingController amountController = TextEditingController();
  final TextEditingController searchController = TextEditingController();

  DateTime date = DateTime.now();
  String? selectedValue;
  List<String> categoryItems = [
    'ادوات ومعدات',
    'مواد ومستلزمات',
    'نقل ومواصلات',
    'اكل ومشروبات',
    'أجور',
    'سلف',
    'عمال',
    'اخرى',
  ];

  // حالة التعديل
  String? _editingExpenseId;
  bool _isEditing = false;

  Timer? _syncTimer;

  ExpenseController({required this.userId})
      : _model = ExpenseModel(userId: userId) {
    _init();
  }

  Future<void> _init() async {
    await _model.initStorage();
    expenses = List.from(_model.localExpenses);
    await _checkConnectivity();
    _startPeriodicSync();
    isLoading = false;
    notifyListeners();
  }

  // ========== الاتصال ==========
  Future<void> _checkConnectivity() async {
    final hasInternet = await _model.hasInternet();
    isOffline = !hasInternet;
    notifyListeners();
    if (hasInternet) await _syncWithFirestore();
  }

  // ========== المزامنة ==========
  Future<void> _syncWithFirestore() async {
    try {
      await _model.syncWithFirestore(expenses);
      await _model.loadLocalExpenses();
      expenses = List.from(_model.localExpenses);
      notifyListeners();
    } catch (e) {
      print('فشل المزامنة: $e');
    }
  }

  void _startPeriodicSync() {
    _syncTimer = Timer.periodic(Duration(minutes: 5), (timer) async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) await _syncWithFirestore();
    });
  }

  // ========== عمليات المصروفات ==========
  Future<bool> addExpense(BuildContext context) async {
    if (AdminSessionService.instance.role != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('حساب المدير مخصص للإدارة والإشراف فقط، ولا يمكنه إضافة مصروفات.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canCreate(TeamPermissions.expenses)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية إضافة مصروفات.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (!formKey.currentState!.validate()) return false;

    final expenseId = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();
    final actor = MemberSessionService.instance.actor;

    Map<String, dynamic> expenseData = {
      'id': expenseId,
      'description': descriptionController.text,
      'amount': double.parse(amountController.text),
      'category': selectedValue ?? 'اخرى',
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': createdAt,
      'createdByLabel': actor.label,
      'createdByRole': actor.role,
      'createdByUid': actor.uid,
    };

    expenses.insert(0, expenseData);
    await _model.saveExpensesToFile(expenses);
    notifyListeners();

    unawaited(() async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        try {
          await _model.saveExpenseToFirestore(expenseData, false);
          final index = expenses.indexWhere((e) => e['id'] == expenseId);
          if (index != -1) {
            expenses[index]['synced'] = 1;
            await _model.saveExpensesToFile(expenses);
          }
          notifyListeners();
        } catch (e) {
          print('فشل رفع المصروف: $e');
        }
      }
      await ActivityService.recordActivity(userId: userId);
      await AnalyticsService.instance.logExpenseAdded();
    }());
    _resetForm();
    return true;
  }

  Future<bool> editExpense(BuildContext context) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canUpdate(TeamPermissions.expenses)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('لا تملك صلاحية تعديل المصروفات.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return false;
    }

    if (!formKey.currentState!.validate() || _editingExpenseId == null) return false;

    final index = expenses.indexWhere((e) => e['id'] == _editingExpenseId);
    if (index == -1) return false;

    final existing = expenses[index];
    final actor = MemberSessionService.instance.actor;

    Map<String, dynamic> updatedData = {
      'id': _editingExpenseId,
      'description': descriptionController.text,
      'amount': double.parse(amountController.text),
      'category': selectedValue ?? 'اخرى',
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': expenses[index]['createdAt'],
      'createdByLabel': existing['createdByLabel'],
      'createdByRole': existing['createdByRole'],
      'createdByUid': existing['createdByUid'],
      'lastModifiedByLabel': actor.label,
      'lastModifiedByRole': actor.role,
      'lastModifiedByUid': actor.uid,
    };

    expenses[index] = updatedData;
    await _model.saveExpensesToFile(expenses);
    notifyListeners();

    unawaited(() async {
      final hasInternet = await _model.hasInternet();
      if (hasInternet) {
        try {
          await _model.saveExpenseToFirestore(updatedData, true);
          expenses[index]['synced'] = 1;
          await _model.saveExpensesToFile(expenses);
          notifyListeners();
        } catch (e) {
          print('فشل تحديث المصروف: $e');
        }
      }
    }());
    _resetForm();
    return true;
  }

  Future<void> deleteExpense(String expenseId) async {
    if (MemberSessionService.instance.isSubUser &&
        !MemberSessionService.instance.canDelete(TeamPermissions.expenses)) {
      return;
    }

    expenses.removeWhere((e) => e['id'] == expenseId);
    await _model.saveExpensesToFile(expenses);
    notifyListeners();

    final hasInternet = await _model.hasInternet();
    if (hasInternet) {
      try {
        await _model.deleteExpenseFromFirestore(expenseId);
      } catch (e) {
        print('فشل حذف المصروف من السحاب: $e');
      }
    }
  }

  // ========== تحميل بيانات المصروف للتعديل ==========
  void loadExpenseForEditing(Map<String, dynamic> expense) {
    descriptionController.text = expense['description'] ?? '';
    amountController.text = expense['amount']?.toString() ?? '';
    selectedValue = expense['category'] ?? 'اخرى';
    try {
      date = DateTime.parse(expense['date']);
    } catch (_) {
      date = DateTime.now();
    }
    _editingExpenseId = expense['id'];
    _isEditing = true;
    notifyListeners();
  }

  void _resetForm() {
    descriptionController.clear();
    amountController.clear();
    selectedValue = null;
    date = DateTime.now();
    _editingExpenseId = null;
    _isEditing = false;
    notifyListeners();
  }

  bool get isEditing => _isEditing;
  String? get editingExpenseId => _editingExpenseId;

  // ========== التصفية ==========
  List<Map<String, dynamic>> get filteredExpenses {
    final searchText = searchController.text.toLowerCase();
    return expenses.where((expense) {
      final matchesSearch = searchText.isEmpty ||
          expense['description']?.toLowerCase().contains(searchText) == true;
      final matchesCategory =
          selectedCategory == "الكل" || expense['category'] == selectedCategory;
      return matchesSearch && matchesCategory;
    }).toList();
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

  void setCategory(String? value) {
    selectedValue = value;
    notifyListeners();
  }

  void updateSearch(String value) {
    // يتم التحديث تلقائياً عبر البحث
    notifyListeners();
  }

  // ========== التنظيف ==========
  @override
  void dispose() {
    _syncTimer?.cancel();
    descriptionController.dispose();
    amountController.dispose();
    searchController.dispose();
    super.dispose();
  }

  // ========== المزامنة اليدوية (للزر) ==========
  Future<void> syncNow() async {
    await _syncWithFirestore();
  }

  void resetForm() {
    _resetForm();
  }
}