// lib/admin/controllers/admin_notifications_controller.dart
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TextEditingController;

import '../models/admin_models.dart';
import '../services/admin_firestore_service.dart';

class AdminNotificationsController extends ChangeNotifier {
  List<NotificationRequest> history = [];
  bool isLoading = true;
  bool isSending = false;
  String? error;
  String? successMessage;
  bool? notificationsEnabled;

  final titleController = TextEditingController();
  final bodyController = TextEditingController();
  String? targetType; // all | user
  String? targetUid;
  String? targetEmail;

  bool _titleDirty = false;
  bool _bodyDirty = false;
  DateTime? _lastBulkSentAt;

  static const int maxTitle = 60;
  static const int maxBody = 200;
  static const Duration _bulkRateLimit = Duration(minutes: 10);

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _disposed = false;

  AdminNotificationsController() {
    targetType = 'all';
    titleController.addListener(_onTextChanged);
    bodyController.addListener(_onTextChanged);
  }

  bool get titleInvalid => _titleDirty && titleController.text.trim().isEmpty;
  bool get bodyInvalid => _bodyDirty && bodyController.text.trim().isEmpty;

  /// زر الإرسال معطّل حتى تصح كل الحقول (حسب المواصفات).
  bool get canSend {
    if (notificationsEnabled == false) return false;
    if (titleController.text.trim().isEmpty) return false;
    if (bodyController.text.trim().isEmpty) return false;
    if (targetType == 'user' && (targetUid == null || targetUid!.isEmpty)) return false;
    if (targetType == 'all' && bulkRateLimited) return false;
    return true;
  }

  /// حد أقصى لإرسال إشعار جماعي واحد كل 10 دقائق (قيد في الواجهة).
  bool get bulkRateLimited {
    final last = _lastBulkSentAt;
    if (last == null) return false;
    return DateTime.now().difference(last) < _bulkRateLimit;
  }

  int get remainingTitle => (maxTitle - titleController.text.length).clamp(0, maxTitle);
  int get remainingBody => (maxBody - bodyController.text.length).clamp(0, maxBody);

  void _onTextChanged() {
    if (titleController.text.isNotEmpty) _titleDirty = true;
    if (bodyController.text.isNotEmpty) _bodyDirty = true;
    notifyListeners();
  }

  void load() {
    isLoading = true;
    error = null;
    notifyListeners();
    _loadNotificationsEnabled();
    _sub?.cancel();
    _sub = AdminFirestoreService.instance.notificationsStream().listen(
          (snap) {
            history = snap.docs.map(NotificationRequest.fromDoc).toList();
            isLoading = false;
            notifyListeners();
          },
          onError: (e) {
            error = e.toString();
            isLoading = false;
            notifyListeners();
          },
        );
  }

  /// هل الإشعارات مفعّلة عموماً من platform/app_config (notificationsEnabled)؟
  Future<void> _loadNotificationsEnabled() async {
    try {
      final cfg = await AdminFirestoreService.instance.fetchAppConfig();
      notificationsEnabled = cfg.notificationsEnabled;
    } catch (_) {
      notificationsEnabled = null;
    }
    if (!_disposed) notifyListeners();
  }

  void setTargetType(String value) {
    targetType = value;
    notifyListeners();
  }

  void setTargetUser(String uid, String email) {
    targetUid = uid;
    targetEmail = email;
    notifyListeners();
  }

  Future<bool> send({required String createdBy}) async {
    if (notificationsEnabled == false) {
      error = 'الإشعارات معطلة حالياً من إعدادات المنصة';
      notifyListeners();
      return false;
    }
    final title = titleController.text.trim();
    final body = bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      error = 'أدخل عنوان الإشعار ونصّه';
      notifyListeners();
      return false;
    }
    if (targetType == 'user' && (targetUid == null || targetUid!.isEmpty)) {
      error = 'حدّد المستخدم المستهدف';
      notifyListeners();
      return false;
    }
    if (targetType == 'all' && bulkRateLimited) {
      error = 'لا يمكن إرسال إشعار جماعي أكثر من مرة كل 10 دقائق';
      notifyListeners();
      return false;
    }

    isSending = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      await AdminFirestoreService.instance.createNotification(
        title: title,
        body: body,
        targetType: targetType ?? 'all',
        targetUid: targetType == 'user' ? targetUid : null,
        createdBy: createdBy,
      );
      if (targetType == 'all') _lastBulkSentAt = DateTime.now();
      successMessage = 'تم إرسال طلب الإشعار';
      titleController.clear();
      bodyController.clear();
      targetUid = null;
      targetEmail = null;
      targetType = 'all';
      isSending = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isSending = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    titleController.dispose();
    bodyController.dispose();
    super.dispose();
  }
}