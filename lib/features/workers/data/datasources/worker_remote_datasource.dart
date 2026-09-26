// lib/features/workers/data/datasources/worker_remote_datasource.dart
// المسؤول الوحيد عن الاتصال بـ Firestore لجدول العمال
// (users/{userId}/workers). منقولة حرفياً من WorkersModel القديم.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';

class WorkerRemoteDataSource {
  WorkerRemoteDataSource._();
  static final WorkerRemoteDataSource instance = WorkerRemoteDataSource._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static const int whereInChunkSize = 30;

  CollectionReference<Map<String, dynamic>> _workersOf(String userId) =>
      _firestore.collection('users').doc(userId).collection('workers');

  // ============================== الدفع (Upload) ==============================

  /// رفع عامل واحد غير متزامن إلى السحاب (إنشاء أو تحديث مع آخر وقت تعديل).
  Future<void> uploadWorker(String userId, Map<String, dynamic> worker) async {
    final id = worker['id'];
    final docRef = _workersOf(userId).doc(id);

    Map<String, dynamic> firestoreData = Map.from(worker);
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

  // ============================== السحب (Download) ==============================

  /// جلب العمال المفوَّضين فقط (تفويض على مستوى السجل) عبر whereIn مجزأة.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchWorkersByRecordIds(String userId, List<String> ids) async {
    final snapshots = <QuerySnapshot<Map<String, dynamic>>>[];
    for (var i = 0; i < ids.length; i += whereInChunkSize) {
      final chunk = ids.sublist(
          i, i + whereInChunkSize > ids.length ? ids.length : i + whereInChunkSize);
      if (chunk.isEmpty) continue;
      snapshots.add(await _workersOf(userId)
          .where(FieldPath.documentId, whereIn: chunk)
          .get());
    }
    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final s in snapshots) {
      docs.addAll(s.docs);
    }
    return docs;
  }

  /// جلب كل العمال (أول مزامنة).
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchAllWorkers(
          String userId) async =>
      (await _workersOf(userId).get()).docs;

  /// جلب العمال الجدد (createdAt) منذ آخر مزامنة.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchNewWorkersSince(String userId, Timestamp since) async =>
          (await _workersOf(userId)
                  .where('createdAt', isGreaterThan: since)
                  .get())
              .docs;

  /// جلب العمال المعدَّلين (updatedAt) منذ آخر مزامنة.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      fetchUpdatedWorkersSince(String userId, Timestamp since) async =>
          (await _workersOf(userId)
                  .where('updatedAt', isGreaterThan: since)
                  .get())
              .docs;

  // ============================== الحفظ والحذف ==============================

  /// حفظ أو تحديث عامل كامل في السحاب.
  Future<void> saveWorker(
      String userId, Map<String, dynamic> worker, bool isEditing) async {
    final id = worker['id'];
    final docRef = _workersOf(userId).doc(id);

    Map<String, dynamic> firestoreData = Map.from(worker);
    firestoreData.remove('id');
    firestoreData.remove('synced');
    if (firestoreData['date'] is String) {
      firestoreData['date'] =
          Timestamp.fromDate(DateTime.parse(firestoreData['date']));
    }

    final docSnapshot = await docRef.get();
    FirebaseUsageTracker.instance.recordRead();
    if (docSnapshot.exists) {
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

  /// حذف عامل من السحاب.
  Future<void> deleteWorker(String userId, String workerId) async {
    await _workersOf(userId).doc(workerId).delete();
    FirebaseUsageTracker.instance.recordDelete();
  }
}