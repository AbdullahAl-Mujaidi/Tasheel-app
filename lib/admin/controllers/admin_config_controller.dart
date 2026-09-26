// lib/admin/controllers/admin_config_controller.dart
// مشترك بين "إصدارات التطبيق" و"إعدادات المنصة".
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TextEditingController;

import '../models/admin_models.dart';
import '../services/admin_api.dart';
import '../services/admin_firestore_service.dart';

class AdminConfigController extends ChangeNotifier {
  AppConfig config = AppConfig.defaultConfig;
  DashboardStats? stats;
  bool isLoading = true;
  bool isSaving = false;
  String? error;
  String? success;

  // حقول النسخة
  final appNameController = TextEditingController();
  final currentVersionController = TextEditingController();
  final minVersionController = TextEditingController();
  final updateUrlController = TextEditingController();
  final releaseNotesController = TextEditingController();
  bool forceUpdate = false;
  bool notificationsEnabled = true;

  // تتبّع تفاعل المستخدم مع الحقول للتحقق الفوري
  bool _curDirty = false;
  bool _minDirty = false;
  bool _urlDirty = false;

  static const int maxReleaseNotes = 500;

  AdminConfigController() {
    currentVersionController.addListener(_onFieldChanged);
    minVersionController.addListener(_onFieldChanged);
    updateUrlController.addListener(_onFieldChanged);
    releaseNotesController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (currentVersionController.text.isNotEmpty) _curDirty = true;
    if (minVersionController.text.isNotEmpty) _minDirty = true;
    if (updateUrlController.text.isNotEmpty) _urlDirty = true;
    notifyListeners();
  }

  String get currentVersion => currentVersionController.text.trim();
  String get minVersion => minVersionController.text.trim();

  String get _currentVersion => currentVersionController.text.trim();
  String get _minVersion => minVersionController.text.trim();

  bool get currentVersionValid =>
      _currentVersion.isNotEmpty && _isSemver(_currentVersion);

  bool get updateUrlValid {
    final u = updateUrlController.text.trim();
    if (u.isEmpty) return false;
    final uri = Uri.tryParse(u);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  bool get minVersionValid {
    if (_minVersion.isEmpty) return false;
    if (!_isSemver(_minVersion)) return false;
    if (currentVersionValid && _compareSemver(_minVersion, _currentVersion) > 0) {
      return false;
    }
    return true;
  }

  bool get canSaveVersions => currentVersionValid && minVersionValid && updateUrlValid;
  bool get canSavePlatform => appNameController.text.trim().isNotEmpty;

  String? get currentVersionError {
    if (_curDirty && _currentVersion.isEmpty) return 'الإصدار الحالي مطلوب';
    if (_currentVersion.isNotEmpty && !_isSemver(_currentVersion)) {
      return 'صيغة غير صحيحة (مثال: 1.2.0)';
    }
    return null;
  }

  String? get minVersionError {
    if (_minDirty && _minVersion.isEmpty) return 'الحد الأدنى مطلوب';
    if (_minVersion.isNotEmpty && !_isSemver(_minVersion)) {
      return 'صيغة غير صحيحة (مثال: 1.2.0)';
    }
    if (currentVersionValid && _compareSemver(_minVersion, _currentVersion) > 0) {
      return 'لا يمكن أن يتجاوز الإصدار الحالي';
    }
    return null;
  }

  String? get updateUrlError {
    if (_urlDirty && updateUrlController.text.trim().isEmpty) return 'رابط التحديث مطلوب';
    if (updateUrlController.text.trim().isNotEmpty && !updateUrlValid) {
      return 'صيغة الرابط غير صحيحة';
    }
    return null;
  }

  int get remainingReleaseNotes =>
      (maxReleaseNotes - releaseNotesController.text.length).clamp(0, maxReleaseNotes);

  bool _isSemver(String v) => RegExp(r'^\d+\.\d+\.\d+$').hasMatch(v.trim());

  List<int> _semverParts(String v) => v
      .trim()
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();

  int _compareSemver(String a, String b) {
    final pa = _semverParts(a);
    final pb = _semverParts(b);
    for (int i = 0; i < 3; i++) {
      final va = i < pa.length ? pa[i] : 0;
      final vb = i < pb.length ? pb[i] : 0;
      if (va != vb) return va.compareTo(vb);
    }
    return 0;
  }

  Future<void> load() async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      config = await AdminFirestoreService.instance.fetchAppConfig();
      stats = await AdminFirestoreService.instance.fetchDashboardStats();
      _syncControllers();
    } catch (e) {
      error = e.toString();
    }
    isLoading = false;
    notifyListeners();
  }

  void _syncControllers() {
    appNameController.text = config.appName;
    currentVersionController.text = config.currentVersion;
    minVersionController.text = config.minVersion;
    updateUrlController.text = config.updateUrl;
    releaseNotesController.text = config.releaseNotes;
    forceUpdate = config.forceUpdate;
    notificationsEnabled = config.notificationsEnabled;
  }

  void setForceUpdate(bool v) {
    forceUpdate = v;
    notifyListeners();
  }

  void setNotificationsEnabled(bool v) {
    notificationsEnabled = v;
    notifyListeners();
  }

  /// حفظ حقول "إصدارات التطبيق" فقط (كتابة جزئية Merge — لا يمسّ
  /// حقول إعدادات المنصة حتى لا تُمسح تعديلات الصفحة الأخرى).
  Future<bool> saveVersions() {
    return _savePatch({
      'currentVersion': _currentVersion,
      'minVersion': _minVersion,
      'updateUrl': updateUrlController.text.trim(),
      'releaseNotes': releaseNotesController.text.trim(),
      'forceUpdate': forceUpdate,
    });
  }

  /// حفظ حقول "إعدادات المنصة" فقط (كتابة جزئية Merge).
  Future<bool> savePlatform() {
    return _savePatch({
      'appName': appNameController.text.trim().isNotEmpty
          ? appNameController.text.trim()
          : 'تسهيل',
      'notificationsEnabled': notificationsEnabled,
    });
  }

  Future<bool> _savePatch(Map<String, dynamic> patch) async {
    isSaving = true;
    error = null;
    success = null;
    notifyListeners();
    try {
      await AdminApi.instance.updateAppConfig(patch);
      await load();
      success = 'تم حفظ الإعدادات وتسجيل العملية في سجل العمليات';
      isSaving = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = e.toString();
      isSaving = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    appNameController.dispose();
    currentVersionController.dispose();
    minVersionController.dispose();
    updateUrlController.dispose();
    releaseNotesController.dispose();
    super.dispose();
  }
}