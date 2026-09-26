// lib/controller/app_usage_controller.dart
// متحكم صفحة "استهلاك التطبيق" — يقرأ عدّاد عمليات التطبيق المحلي فقط
// (SQLite) ولا يجلب أي استهلاك رسمي من Firebase نهائيًا.
import 'package:flutter/foundation.dart';

import '../admin/models/firebase_usage_model.dart';
import '../admin/services/firebase_usage_tracker.dart';

class AppUsageController extends ChangeNotifier {
  FirestoreOps today = const FirestoreOps.empty();
  FirestoreOps totals = const FirestoreOps.empty();
  List<FirestoreOps> last7Days = const <FirestoreOps>[];
  bool _disposed = false;

  Future<void> load() async {
    await FirebaseUsageTracker.instance.init();
    today = FirebaseUsageTracker.instance.today();
    totals = FirebaseUsageTracker.instance.totals();
    last7Days = FirebaseUsageTracker.instance.lastDays(7);
    notifyListeners();
  }

  /// إعادة ضبط عدّادات التطبيق المحلية (تُستدعى بعد تأكيد المستخدم).
  Future<void> reset() async {
    await FirebaseUsageTracker.instance.reset();
    await load();
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}