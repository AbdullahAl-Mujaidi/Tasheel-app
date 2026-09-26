// lib/admin/screens/sync_status_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_sync_controller.dart';
import '../controllers/admin_users_controller.dart';
import '../models/admin_models.dart';
import '../widgets/common.dart';
import 'user_details_screen.dart';

class AdminSyncStatusScreen extends StatelessWidget {
  const AdminSyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminSyncController()..load(),
      child: Consumer<AdminSyncController>(
        builder: (context, c, _) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('حالة المزامنة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: c.isLoading ? null : () => c.load(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'تحديث',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      sectionTitle(context, 'مهم: طبيعة البيانات المعروضة'),
                      const Text('• التطبيق يعمل بنظام Offline-first: بيانات كل مستخدم تُخزَّن محلياً على جهازه وتُرفع عند توفر الاتصال.'),
                      const SizedBox(height: 6),
                      const Text('• قوائم العمليات المعلقة وأخطاء المزامنة تُحفظ محلياً فقط ولا تصل إلى الخادم، لذلك لا يمكن للمدير رؤيتها عن بُعد.'),
                      const SizedBox(height: 6),
                      const Text('• ما يظهر هنا هو ما يبلغه التطبيق للخادم: آخر تسجيل دخول، آخر نشاط، وآخر مزامنة ناجحة.'),
                    ],
                  ),
                ),
              ),
              if (c.stoppedCount >= AdminSyncController.alertThreshold) ...[
                const SizedBox(height: 16),
                _stoppedAlert(context, c),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (v) => c.query = v,
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو البريد...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: c.statusFilter,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('الكل')),
                      DropdownMenuItem(value: 'upToDate', child: Text('محدّث')),
                      DropdownMenuItem(value: 'delayed', child: Text('متأخر')),
                      DropdownMenuItem(value: 'stopped', child: Text('متوقف')),
                    ],
                    onChanged: (v) {
                      if (v != null) c.statusFilter = v;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (c.isLoading)
                loadingWidget()
              else if (c.error != null)
                errorBanner(context, c.error!, onRetry: c.load)
              else if (c.users.isEmpty)
                _emptyResult(context, c)
              else
                Column(
                  children: [
                    for (final u in c.users)
                      _userCard(context, c, u),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _stoppedAlert(BuildContext context, AdminSyncController c) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.orange.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => c.statusFilter = 'stopped',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${c.stoppedCount} حساب متوقف عن المزامنة',
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSurface),
                ),
              ),
              const Icon(Icons.filter_alt_outlined, size: 18, color: Colors.orange),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyResult(BuildContext context, AdminSyncController c) {
    if (c.query.trim().isEmpty && c.statusFilter == 'all') {
      return emptyState(context, 'لا يوجد بيانات مزامنة لعرضها', icon: Icons.sync_outlined);
    }
    return Column(
      children: [
        emptyState(context, 'لا توجد نتائج مطابقة', icon: Icons.search_off_outlined),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {
            c.query = '';
            c.statusFilter = 'all';
          },
          icon: const Icon(Icons.refresh),
          label: const Text('إعادة تعيين الفلتر'),
        ),
      ],
    );
  }

  Widget _userCard(BuildContext context, AdminSyncController c, UserSnapshot u) {
    final scheme = Theme.of(context).colorScheme;
    final category = AdminSyncController.categoryOf(u);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      child: ListTile(
        title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(u.email),
            Text(
              'آخر مزامنة: ${formatDate(u.lastSyncAt)} • آخر نشاط: ${formatDate(u.lastActivityAt)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (u.appVersion.isNotEmpty)
              Text(
                'إصدار التطبيق: ${u.appVersion}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
          ],
        ),
        isThreeLine: true,
        trailing: _categoryChip(category),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserDetailsScreen(user: u, controller: AdminUsersController()),
          ),
        ),
      ),
    );
  }

  Widget _categoryChip(SyncCategory category) {
    final MaterialColor color;
    switch (category) {
      case SyncCategory.upToDate:
        color = Colors.green;
      case SyncCategory.delayed:
        color = Colors.orange;
      case SyncCategory.stopped:
        color = Colors.red;
      case SyncCategory.unknown:
        color = Colors.grey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(
        AdminSyncController.labelOf(category),
        style: TextStyle(color: color.shade800, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}