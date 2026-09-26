// lib/admin/controllers/admin_audit_controller.dart
import 'package:flutter/foundation.dart';

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';

class AdminAuditController extends ChangeNotifier {
  List<AuditLogEntry> logs = [];
  bool isLoading = true;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      logs = await AdminFirestoreService.instance.fetchAuditLogs();
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }
}