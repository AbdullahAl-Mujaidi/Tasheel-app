// lib/models/expense_model.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExpenseModel {
  final String userId;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  File? _expensesFile;
  List<Map<String, dynamic>> _localExpenses = [];

  ExpenseModel({required this.userId});

  // ========== التخزين المحلي ==========
  Future<void> initStorage() async {
    try {
      final Directory appDir = await getApplicationDocumentsDirectory();
      final String expensesDirPath = '${appDir.path}/expenses_data';
      final Directory expensesDir = Directory(expensesDirPath);
      if (!await expensesDir.exists()) {
        await expensesDir.create(recursive: true);
      }
      final String filePath = '$expensesDirPath/expenses_$userId.json';
      _expensesFile = File(filePath);
      await loadLocalExpenses();
    } catch (e) {
      print('خطأ في تهيئة التخزين: $e');
      rethrow;
    }
  }

  Future<void> loadLocalExpenses() async {
    if (_expensesFile == null) return;
    try {
      if (await _expensesFile!.exists()) {
        final String jsonString = await _expensesFile!.readAsString();
        final List<dynamic> jsonList = json.decode(jsonString);
        _localExpenses = jsonList.cast<Map<String, dynamic>>();
      } else {
        _localExpenses = [];
      }
    } catch (e) {
      print('خطأ في تحميل المصروفات: $e');
      _localExpenses = [];
    }
  }

  Future<void> saveExpensesToFile(List<Map<String, dynamic>> expenses) async {
    if (_expensesFile == null) return;
    try {
      final String jsonString = json.encode(expenses);
      await _expensesFile!.writeAsString(jsonString);
    } catch (e) {
      print('خطأ في حفظ المصروفات: $e');
      rethrow;
    }
  }

  List<Map<String, dynamic>> get localExpenses => _localExpenses;

  // ========== الاتصال بالإنترنت ==========
  Future<bool> hasInternet() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ========== المزامنة مع Firestore ==========
  Future<void> syncWithFirestore(List<Map<String, dynamic>> expenses) async {
    if (_expensesFile == null) return;
    final bool internetAvailable = await hasInternet();
    if (!internetAvailable) return;

    try {
      // رفع المصروفات غير المتزامنة
      final List<Map<String, dynamic>> unsynced =
          expenses.where((e) => e['synced'] == 0).toList();
      for (var expense in unsynced) {
        await _uploadExpense(expense);
        final index = expenses.indexWhere((e) => e['id'] == expense['id']);
        if (index != -1) expenses[index]['synced'] = 1;
      }
      if (unsynced.isNotEmpty) await saveExpensesToFile(expenses);

      // تحميل المصروفات الجديدة من السحاب
      final lastSyncTime = await _getLastSyncTime();
      final QuerySnapshot cloudExpenses = await firestore
          .collection('users')
          .doc(userId)
          .collection('expenses')
          .where('createdAt', isGreaterThan: lastSyncTime)
          .get();

      int addedCount = 0;
      for (var doc in cloudExpenses.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        if (!expenses.any((e) => e['id'] == id)) {
          expenses.add({
            'id': id,
            'description': data['description'],
            'amount': data['amount'],
            'category': data['category'],
            'date': (data['date'] as Timestamp).toDate().toIso8601String(),
            'synced': 1,
            'createdAt': data['createdAt'] ?? DateTime.now().toIso8601String(),
          });
          addedCount++;
        }
      }

      expenses.sort((a, b) => b['date'].compareTo(a['date']));
      if (addedCount > 0) await saveExpensesToFile(expenses);
      await _saveLastSyncTime(DateTime.now().toIso8601String());
    } catch (e) {
      print('خطأ في المزامنة: $e');
      rethrow;
    }
  }

  Future<void> _uploadExpense(Map<String, dynamic> expense) async {
    final id = expense['id'];
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .doc(id);

    Map<String, dynamic> firestoreData = Map.from(expense);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    if (firestoreData['date'] is String) {
      firestoreData['date'] = Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }

    final docSnapshot = await docRef.get();
    if (!docSnapshot.exists) {
      await docRef.set(firestoreData);
    } else {
      await docRef.update({
        ...firestoreData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<String> _getLastSyncTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('last_sync_$userId') ?? '2000-01-01';
  }

  Future<void> _saveLastSyncTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_sync_$userId', time);
  }

  // حفظ أو تحديث مصروف في السحاب
  Future<void> saveExpenseToFirestore(Map<String, dynamic> expense, bool isEditing) async {
    final id = expense['id'];
    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .doc(id);

    Map<String, dynamic> firestoreData = Map.from(expense);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    if (firestoreData['date'] is String) {
      firestoreData['date'] = Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }

    if (isEditing) {
      await docRef.update({
        ...firestoreData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.set({
        ...firestoreData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // حذف من السحاب
  Future<void> deleteExpenseFromFirestore(String expenseId) async {
    await firestore
        .collection('users')
        .doc(userId)
        .collection('expenses')
        .doc(expenseId)
        .delete();
  }
}