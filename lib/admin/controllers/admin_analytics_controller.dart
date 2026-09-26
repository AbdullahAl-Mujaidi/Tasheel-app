// lib/admin/controllers/admin_analytics_controller.dart
import 'package:flutter/foundation.dart';

import '../models/admin_models.dart';
import '../services/admin_api.dart';
import '../services/admin_firestore_service.dart';

class AdminAnalyticsController extends ChangeNotifier {
  DashboardStats? stats;
  bool isLoading = true;
  bool isRefreshing = false;
  String? error;

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      stats = await AdminFirestoreService.instance.fetchDashboardStats();
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    isRefreshing = true;
    notifyListeners();
    try {
      await AdminApi.instance.refreshStats();
    } catch (e) {
      error = e.toString();
    }
    await load();
  }
}