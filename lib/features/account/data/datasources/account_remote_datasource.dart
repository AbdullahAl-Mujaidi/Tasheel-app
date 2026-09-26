// lib/features/account/data/datasources/account_remote_datasource.dart
// المسؤول الوحيد عن الاتصال بـ Firebase لإنشاء الحساب: FirebaseAuth
// (إنشاء/تسجيل دخول/تحقق بريد) وFirestore (users/{uid}). منقول حرفياً
// من AccountModel القديم.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/admin/services/firebase_usage_tracker.dart';
import 'package:fkra/core/constants/app_constants.dart';

class AccountRemoteDataSource {
  AccountRemoteDataSource._();
  static final AccountRemoteDataSource instance = AccountRemoteDataSource._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<UserCredential> createUserWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _auth.createUserWithEmailAndPassword(email: email, password: password);

  Future<UserCredential> signInWithEmailPassword({
    required String email,
    required String password,
  }) =>
      _auth.signInWithEmailAndPassword(email: email, password: password);

  /// إرسال رسالة التحقق من البريد للمستخدم الحالي (لا يوقف الاكتمال).
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user != null && !user.emailVerified) {
      await user.sendEmailVerification();
    }
  }

  /// كتابة ملف تعريفي لحساب أُنشئ أو استُكمل من قائمة المعلّقة — merge: true
  /// (نفس سلوك AccountModel.syncPendingAccounts).
  Future<void> saveSyncedProfile(
      String userId, Map<String, dynamic> userData) async {
    Map<String, dynamic> firestoreData = {
      'userId': userId,
      'fullName': userData['fullName'],
      'businessName': userData['businessName'],
      'phoneNumber': userData['phoneNumber'],
      'email': userData['email'],
      'userType': userData['userType'] ?? 'user',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
    await _firestore
        .collection(FirestoreCollections.users)
        .doc(userId)
        .set(firestoreData, SetOptions(merge: true));
    FirebaseUsageTracker.instance.recordWrite();
  }

  /// حفظ بيانات المستخدم (تحديث الحقول المسموح بها فقط إذا وُجد المستند،
  /// وإلا إنشاء — تتوافق مع firestore.rules).
  Future<void> saveUserDataToFirestore({
    required String userId,
    required Map<String, dynamic> userData,
  }) async {
    final ref = _firestore.collection(FirestoreCollections.users).doc(userId);
    final doc = await ref.get();
    FirebaseUsageTracker.instance.recordRead();
    if (doc.exists) {
      await ref.update({
        'fullName': userData['fullName'],
        'businessName': userData['businessName'],
        'phoneNumber': userData['phoneNumber'],
        'email': userData['email'],
      });
    } else {
      Map<String, dynamic> firestoreData = {
        'userId': userId,
        'fullName': userData['fullName'],
        'businessName': userData['businessName'],
        'phoneNumber': userData['phoneNumber'],
        'email': userData['email'],
        'userType': userData['userType'] ?? 'user',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await ref.set(firestoreData);
    }
    FirebaseUsageTracker.instance.recordWrite();
  }
}