// lib/features/dashboard/data/datasources/dashboard_remote_datasource.dart
// المسؤول الوحيد عن جلب بيانات التجمعات من Firestore للوحة البداية
// والتقارير. منقول حرفياً من HomeModel/ReportModel القديمين.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';

class DashboardRemoteDataSource {
  DashboardRemoteDataSource._();
  static final DashboardRemoteDataSource instance =
      DashboardRemoteDataSource._();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// جلب كامل مجموعة فرعية تحت users/{uid} وتسجيل عدد القراءات.
  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> fetchCollection(
      String userId, String collection) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection(collection)
        .get();
    FirebaseUsageTracker.instance.recordReads(snapshot.docs.length);
    return snapshot.docs;
  }
}