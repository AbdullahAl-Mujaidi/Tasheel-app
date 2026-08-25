// lib/controllers/expense_controller.dart
import 'dart:async';
import 'package:fkra/model/expense_model.dart';
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
  Future<void> addExpense(BuildContext context) async {
    if (!formKey.currentState!.validate()) return;

    final expenseId = DateTime.now().millisecondsSinceEpoch.toString();
    final createdAt = DateTime.now().toIso8601String();

    Map<String, dynamic> expenseData = {
      'id': expenseId,
      'description': descriptionController.text,
      'amount': double.parse(amountController.text),
      'category': selectedValue ?? 'اخرى',
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': createdAt,
    };

    expenses.insert(0, expenseData);
    await _model.saveExpensesToFile(expenses);
    notifyListeners();

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
    _resetForm();
  }

  Future<void> editExpense(BuildContext context) async {
    if (!formKey.currentState!.validate() || _editingExpenseId == null) return;

    final index = expenses.indexWhere((e) => e['id'] == _editingExpenseId);
    if (index == -1) return;

    Map<String, dynamic> updatedData = {
      'id': _editingExpenseId,
      'description': descriptionController.text,
      'amount': double.parse(amountController.text),
      'category': selectedValue ?? 'اخرى',
      'date': date.toIso8601String(),
      'synced': 0,
      'createdAt': expenses[index]['createdAt'],
    };

    expenses[index] = updatedData;
    await _model.saveExpensesToFile(expenses);
    notifyListeners();

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
    _resetForm();
  }

  Future<void> deleteExpense(String expenseId) async {
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