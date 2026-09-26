// lib/admin/screens/app_versions_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_config_controller.dart';
import '../models/admin_models.dart';
import '../models/admin_role.dart';
import '../services/admin_session_service.dart';
import '../widgets/common.dart';

class AdminAppVersionsScreen extends StatelessWidget {
  const AdminAppVersionsScreen({super.key});

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
              Text('إصدارات التطبيق', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('يُستخدم هذا القسم لتحديد: أحدث إصدار، الحد الأدنى المدعوم، التحديث الإجباري، ورابط التحديث.',
                  style: TextStyle(color: scheme.onSurfaceVariant)),
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
                        controller: c.currentVersionController,
                        decoration: InputDecoration(
                          labelText: 'الإصدار الحالي',
                          hintText: 'مثال: 1.3.0',
                          border: const OutlineInputBorder(),
                          errorText: c.currentVersionError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: c.minVersionController,
                        decoration: InputDecoration(
                          labelText: 'الحد الأدنى للإصدار (minVersion)',
                          hintText: 'مثال: 1.0.0',
                          border: const OutlineInputBorder(),
                          errorText: c.minVersionError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: c.updateUrlController,
                        decoration: InputDecoration(
                          labelText: 'رابط التحديث (updateUrl)',
                          hintText: 'https://play.google.com/...',
                          border: const OutlineInputBorder(),
                          errorText: c.updateUrlError,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: c.releaseNotesController,
                        maxLines: 3,
                        maxLength: AdminConfigController.maxReleaseNotes,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات الإصدار (releaseNotes)',
                          border: const OutlineInputBorder(),
                          counterText: '${c.remainingReleaseNotes} متبقية',
                        ),
                      ),
                      const SizedBox(height: 4),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('إجبار التحديث (forceUpdate)'),
                        subtitle: const Text('المستخدمون لن يستطيعوا استخدام التطبيق دون التحديث'),
                        value: c.forceUpdate,
                        onChanged: (v) => _onForceUpdateChanged(context, c, v),
                      ),
                      if (c.forceUpdate)
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
                              Expanded(
                                child: Text(
                                  'تحذير: سيُمنع كل من إصداره أقل من ${c.minVersion.isEmpty ? 'الحد الأدنى' : c.minVersion} من استخدام التطبيق',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
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
                        onPressed: _isSuperAdmin && c.canSaveVersions && !c.isSaving
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
              const SizedBox(height: 24),
              sectionTitle(context, 'توزيع الإصدارات الحالي بين المستخدمين'),
              _versionsSummary(context, c.stats),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onForceUpdateChanged(BuildContext context, AdminConfigController c, bool value) async {
    if (value && !c.forceUpdate) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تأكيد تفعيل التحديث الإجباري'),
          content: Text(
            'سيُمنع كل من إصداره أقل من ${c.minVersion.isEmpty ? 'الحد الأدنى المحدد' : c.minVersion} من استخدام التطبيق. متابعة؟',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد التفعيل')),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    c.setForceUpdate(value);
  }

  Future<void> _save(BuildContext context, AdminConfigController c) async {
    final ok = await c.saveVersions();
    if (context.mounted) {
      showSnack(context, ok ? 'تم تحديث إعدادات الإصدار' : 'فشل الحفظ', ok ? SnackKind.success : SnackKind.error);
    }
  }

  Widget _versionsSummary(BuildContext context, DashboardStats? s) {
    if (s == null) {
      return emptyState(context, 'لا توجد بيانات توزيع بعد', icon: Icons.update_outlined);
    }
    final entries = s.versionDistribution.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) {
      return emptyState(context, 'لا توجد بيانات توزيع بعد', icon: Icons.update_outlined);
    }
    final total = entries.fold<int>(0, (a, e) => a + e.value);
    final maxVal = entries.map((e) => e.value).fold(0, (a, b) => a > b ? a : b);
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: scheme.outlineVariant)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const SizedBox(width: 90, child: Text('الإصدار', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  Expanded(child: Text('الانتشار', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 90, child: Text('المستخدمون', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                  SizedBox(width: 60, child: Text('النسبة', textAlign: TextAlign.end, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                ],
              ),
            ),
            for (final e in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    SizedBox(width: 90, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: (e.value / (maxVal <= 0 ? 1 : maxVal)).clamp(0.0, 1.0),
                          minHeight: 8,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 90,
                      child: Text('${e.value} مستخدم', textAlign: TextAlign.end, style: const TextStyle(fontSize: 12)),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        total <= 0 ? '0%' : '${(e.value * 100 / total).toStringAsFixed(1)}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}