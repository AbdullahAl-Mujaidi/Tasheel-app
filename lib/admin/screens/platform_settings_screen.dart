// lib/admin/screens/platform_settings_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_config_controller.dart';
import '../models/admin_role.dart';
import '../services/admin_session_service.dart';
import '../widgets/common.dart';
import 'app_versions_screen.dart';

class AdminPlatformSettingsScreen extends StatelessWidget {
  const AdminPlatformSettingsScreen({super.key});

  bool get _isSuperAdmin {
    final role = AdminSessionService.instance.role;
    return role == AdminRole.superAdmin;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminConfigController()..load(),
      child: Consumer<AdminConfigController>(
        builder: (context, c, _) {
          if (c.isLoading) return loadingWidget();
          final scheme = Theme.of(context).colorScheme;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('إعدادات المنصة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('إعدادات عامة للمنصة (الحفظ الفعلي لـ Super Admin).', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              Card(
                elevation: 0,
                color: scheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: c.appNameController,
                        decoration: InputDecoration(
                          labelText: 'اسم التطبيق (appName)',
                          border: const OutlineInputBorder(),
                          errorText: c.appNameController.text.trim().isEmpty
                              ? 'اسم التطبيق إلزامي'
                              : null,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('تفعيل الإشعارات عموماً (notificationsEnabled)'),
                        subtitle: const Text('عند التعطيل يتوقف إرسال كل الإشعارات لجميع المستخدمين'),
                        value: c.notificationsEnabled,
                        onChanged: (v) => _onNotificationsChanged(context, c, v),
                      ),
                      if (!c.notificationsEnabled)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'الإشعارات معطلة — قسم "الإشعارات" في اللوحة معطّل مؤقتاً',
                                  style: TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const Divider(height: 32),
                      // ملخص إعدادات الإصدار الحالي (للسياق فقط) مع رابط التعديل
                      sectionTitle(context, 'ملخص إعدادات الإصدار الحالي'),
                      _summaryRow(context, 'الإصدار الحالي', c.config.currentVersion.isNotEmpty ? c.config.currentVersion : '-'),
                      _summaryRow(context, 'الحد الأدنى', c.config.minVersion.isNotEmpty ? c.config.minVersion : '-'),
                      // ignore: unnecessary_brace_in_string_interps
                      _summaryRow(context, 'التحديث الإجباري', c.config.forceUpdate ? 'مفعّل' : 'غير مفعّل'),
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => Scaffold(
                                appBar: AppBar(title: const Text('إصدارات التطبيق')),
                                body: const AdminAppVersionsScreen(),
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('تعديل الإعدادات من صفحة إصدارات التطبيق'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!_isSuperAdmin)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: scheme.errorContainer.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'هذا الإجراء يتطلب صلاحية مدير عام',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600),
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: _isSuperAdmin && c.canSavePlatform && !c.isSaving
                            ? () => _save(context, c)
                            : null,
                        icon: c.isSaving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.save),
                        label: c.isSaving ? const Text('جاري الحفظ...') : const Text('حفظ الإعدادات'),
                      ),
                      if (c.error != null) ...[
                        const SizedBox(height: 8),
                        Text(c.error!, style: TextStyle(color: scheme.error)),
                      ],
                      if (c.success != null) ...[
                        const SizedBox(height: 8),
                        Text(c.success!, style: const TextStyle(color: Colors.green)),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: scheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Future<void> _onNotificationsChanged(BuildContext context, AdminConfigController c, bool value) async {
    // تأكيد إلزامي عند تعطيل الإشعارات عموماً (إجراء حرج يُسجَّل في Audit).
    if (!value && c.notificationsEnabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد تعطيل الإشعارات'),
          content: const Text('سيتوقف إرسال كل الإشعارات لجميع المستخدمين حتى إعادة التفعيل. متابعة؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد التعطيل')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    c.setNotificationsEnabled(value);
  }

  Future<void> _save(BuildContext context, AdminConfigController c) async {
    final ok = await c.savePlatform();
    if (context.mounted) {
      showSnack(context, ok ? 'تم تحديث إعدادات المنصة' : 'فشل الحفظ', ok ? SnackKind.success : SnackKind.error);
    }
  }
}