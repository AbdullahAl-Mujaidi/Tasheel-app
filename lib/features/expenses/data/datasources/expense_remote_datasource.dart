// lib/features/expenses/data/datasources/expense_remote_datasource.dart
// المسؤول الوحيد عن الاتصال بـ Firestore لجدول المصروفات
// (users/{userId}/expenses). منقولة حرفياً من ExpenseModel القديم.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';

class ExpenseRemoteDataSource {
  ExpenseRemoteDataSource._();
  static final ExpenseRemoteDataSource instance =
      ExpenseRemoteDataSource._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _expensesOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('expenses');

  /// رفع مصروف واحد غير متزامن إلى السحاب (إنشاء أو تحديث مع آخر وقت تعديل).
  Future<void> uploadExpense(String userId, Map<String, dynamic> expense) async {
    final id = expense['id'];
    final docRef = _expensesOf(userId).doc(id);

    Map<String, dynamic> firestoreData = Map.from(expense);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    if (firestoreData['date'] is String) {
      firestoreData['date'] =
          Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }

    final docSnapshot = await docRef.get();
    FirebaseUsageTracker.instance.recordRead();
    if (!docSnapshot.exists) {
      await docRef.set({
        ...firestoreData,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      await docRef.update({
        ...firestoreData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    FirebaseUsageTracker.instance.recordWrite();
  }

  /// جلب المصروفات من السحاب: كلها عند أول مزامنة، وإلا الجديدة بعد آخر وقت.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchExpenses(
      String userId, {required Timestamp? since}) async {
    final query = _expensesOf(userId);
    if (since == null) return (await query.get()).docs;
    return (await query.where('createdAt', isGreaterThan: since).get()).docs;
  }

  /// حفظ أو تحديث مصروف في السحاب.
  Future<void> saveExpense(
      String userId, Map<String, dynamic> expense, bool isEditing) async {
    final id = expense['id'];
    final docRef = _expensesOf(userId).doc(id);

    Map<String, dynamic> firestoreData = Map.from(expense);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    if (firestoreData['date'] is String) {
      firestoreData['date'] =
          Timestamp.fromDate(DateTime.parse(firestoreData['date']));
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
    FirebaseUsageTracker.instance.recordWrite();
  }

  /// حذف مصروف من السحاب.
  Future<void> deleteExpense(String userId, String expenseId) async {
    await _expensesOf(userId).doc(expenseId).delete();
    FirebaseUsageTracker.instance.recordDelete();
  }
}