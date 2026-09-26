// lib/core/shared/widgets/permission_guard.dart
// حارس موحّد لفحوصات صلاحيات المستخدم التابع.
//
// كل عملية إضافة/تعديل/حذف في المحولات كانت تفتتح بنفس النمط:
//   if (isSubUser && !canX(module)) { showSnackBar('لا تملك صلاحية...'); return; }
// هذا الحارس يجمع النمط مع عرض نفس الرسالة الحمراء، دون أي تغيير في السلوك.
import 'package:flutter/material.dart';

import 'app_feedback.dart';

class PermissionGuard {
  PermissionGuard._();

  /// يتحقق من صلاحية (create/update/delete) للمستخدم التابع.
  /// يعيد false إذا مُنع الوصول (ويعرض رسالة الخطأ)، وtrue للسماح.
  static bool ensure(
    BuildContext context, {
    required bool isSubUser,
    required bool allowed,
    required String deniedMessage,
  }) {
    if (isSubUser && !allowed) {
      AppFeedback.showError(context, deniedMessage);
      return false;
    }
    return true;
  }
}