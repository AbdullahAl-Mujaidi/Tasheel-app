// lib/features/auth/domain/entities/auth_session.dart
// كيان جلسة المصادقة — تمثيل خالص لحالة المستخدم بعد تسجيل الدخول،
// مستقل تماماً عن Firebase (لا يستورد أي مكتبة خارجية).
class AuthSession {
  final String uid;
  final String email;
  final bool emailVerified;

  const AuthSession({
    required this.uid,
    this.email = '',
    this.emailVerified = false,
  });
}