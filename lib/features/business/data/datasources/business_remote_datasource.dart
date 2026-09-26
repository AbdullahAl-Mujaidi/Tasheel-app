// lib/features/business/data/datasources/business_remote_datasource.dart
// المسؤول الوحيد عن الاتصال بـ Firestore لمثلث البيانات
// (users/{userId}/businesses + transactions + custom_fields). منقولة حرفياً
// من BusinessModel القديم بنفس السلوك، ويُمرَّر userId لكل عملية.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';

import '../models/custom_field_codec.dart';

class BusinessRemoteDataSource {
  BusinessRemoteDataSource._();
  static final BusinessRemoteDataSource instance =
      BusinessRemoteDataSource._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int whereInChunkSize = 30;

  CollectionReference<Map<String, dynamic>> _businessesOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('businesses');

  CollectionReference<Map<String, dynamic>> _transactionsOf(
          String userId, String workId) =>
      _businessesOf(userId).doc(workId).collection('transactions');

  // ============================== الدفع (Upload) ==============================

  /// رفع عمل واحد غير متزامن إلى السحاب (إنشاء أو تحديث مع آخر وقت تعديل).
  Future<void> uploadBusiness(String userId, Map<String, dynamic> business) async {
    final id = business['id'];
    final docRef = _businessesOf(userId).doc(id);

    Map<String, dynamic> firestoreData = Map.from(business);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    firestoreData.remove('localId');

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

  /// رفع حركة مالية واحدة غير متزامنة إلى السحاب.
  Future<void> uploadTransaction(String userId, Map<String, dynamic> tx) async {
    final String workId = tx['workId'];
    final docRef = _transactionsOf(userId, workId).doc(tx['id']);

    Map<String, dynamic> firestoreData = Map.from(tx);
    firestoreData.remove('id');
    firestoreData.remove('synced');

    if (firestoreData['date'] is String) {
      firestoreData['date'] =
          Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }
    if (firestoreData['createdAt'] is String) {
      firestoreData['createdAt'] =
          Timestamp.fromDate(DateTime.parse(firestoreData['createdAt']));
    }

    final docSnapshot = await docRef.get();
    FirebaseUsageTracker.instance.recordRead();
    if (!docSnapshot.exists) {
      await docRef.set(firestoreData);
    } else {
      await docRef.update({
        ...firestoreData,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    FirebaseUsageTracker.instance.recordWrite();
  }

  // ============================== السحب (Download) ==============================

  /// جلب الأعمال المفوَّضة فقط (تفويض على مستوى السجل) عبر whereIn مجزأة.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchBusinessesByRecordIds(String userId, List<String> ids) async {
    final snapshots = <QuerySnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += whereInChunkSize) {
      final chunk = ids.sublist(
          i, i + whereInChunkSize > ids.length ? ids.length : i + whereInChunkSize);
      final records = await _businessesOf(userId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      snapshots.add(records);
    }
    return _flattenSnapshots(snapshots);
  }

  /// جلب كل الأعمال (أول مزامنة أو كاش غير مُثبت).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchAllBusinesses(String userId) async =>
          (await _businessesOf(userId).get()).docs;

  /// جلب الأعمال الجديدة (createdAt) منذ آخر مزامنة.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchNewBusinessesSince(String userId, Timestamp since) async =>
          (await _businessesOf(userId)
                  .where('createdAt', isGreaterThan: since)
                  .get())
              .docs;

  /// جلب الأعمال المعدَّلة (updatedAt) منذ آخر مزامنة.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchUpdatedBusinessesSince(String userId, Timestamp since) async =>
          (await _businessesOf(userId)
                  .where('updatedAt', isGreaterThan: since)
                  .get())
              .docs;

  /// جلب حركات عمل واحد (كلها أو منذ آخر مزامنة).
  Future<QuerySnapshot<Map<String, dynamic>>> fetchTransactionsFor(
      String userId,
      String workId, {
      required Timestamp? since}) async {
    final query = _transactionsOf(userId, workId);
    if (since == null) return query.get();
    return query.where('createdAt', isGreaterThan: since).get();
  }

  // ============================== الحقول المخصصة ==============================

  /// جلب الحقول المخصصة من السحاب مرتبة من الأحدث.
  Future<List<Map<String, dynamic>>> fetchCustomFields(String userId) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('custom_fields')
        .orderBy('createdAt', descending: true)
        .get();
    FirebaseUsageTracker.instance.recordReads(snapshot.docs.length);
    return snapshot.docs.map((doc) {
      return sanitizeCustomField({'id': doc.id, ...doc.data()});
    }).toList();
  }

  // ============================== الحذف والتحديث ==============================

  /// حذف عمل من السحاب.
  Future<void> deleteBusiness(String userId, String businessId) async {
    await _businessesOf(userId).doc(businessId).delete();
    FirebaseUsageTracker.instance.recordDelete();
  }

  /// حذف كل حركات عمل من السحاب (دفعة واحدة).
  Future<void> deleteBusinessTransactions(String userId, String workId) async {
    final snapshot = await _transactionsOf(userId, workId).get();
    FirebaseUsageTracker.instance.recordReads(snapshot.docs.length);
    if (snapshot.docs.isEmpty) return;
    final WriteBatch batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    FirebaseUsageTracker.instance.recordDeletes(snapshot.docs.length);
  }

  /// حذف حركة مالية واحدة من السحاب.
  Future<void> deleteTransaction(
      String userId, String workId, String transactionId) async {
    await _transactionsOf(userId, workId).doc(transactionId).delete();
    FirebaseUsageTracker.instance.recordDelete();
  }

  /// تحديث الملخص المالي للعمل في السحاب.
  Future<void> updateBusinessSummary(
    String userId,
    String workId, {
    required int totalPaid,
    required int totalExpenses,
    required int remaining,
  }) async {
    await _businessesOf(userId).doc(workId).update({
      'totalPaid': totalPaid,
      'totalExpenses': totalExpenses,
      'remaining': remaining,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    FirebaseUsageTracker.instance.recordWrite();
  }

  /// حفظ أو تحديث عمل كامل في السحاب.
  Future<void> saveBusiness(
      String userId, Map<String, dynamic> business, bool isEditing) async {
    final id = business['id'];
    final docRef = _businessesOf(userId).doc(id);

    Map<String, dynamic> firestoreData = Map.from(business);
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

  // ============================== أدوات ==============================

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _flattenSnapshots(
      List<QuerySnapshot<Map<String, dynamic>>> snapshots) {
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final s in snapshots) {
      docs.addAll(s.docs);
    }
    return docs;
  }
}