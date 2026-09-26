// lib/core/shared/widgets/app_feedback.dart
// عرض موحّد للرسائل عبر SnackBar.
//
// يحل محل النسخ المتكررة من `ScaffoldMessenger.of(context).showSnackBar(...)`
// مع خلفية حمراء/عادية في المحولات والشاشات، بنفس السلوك البصري تماماً.
import 'package:flutter/material.dart';

class AppFeedback {
  AppFeedback._();

  /// رسالة خطأ (خلفية حمراء) — نفس مظهر SnackBar المستخدم حالياً في المحولات.
  static void showError(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  /// رسالة عامة (الخلفية الافتراضية للموضوع الحالي).
  static void showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}