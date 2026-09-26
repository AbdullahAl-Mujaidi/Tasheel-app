// lib/admin/screens/dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../view/login_view.dart';
import '../controllers/admin_dashboard_controller.dart';
import '../controllers/admin_users_controller.dart';
import '../models/admin_models.dart';
import '../services/admin_session_service.dart';
import '../widgets/common.dart';
import 'user_details_screen.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Future<void> _refresh(BuildContext context) async {
    final c = context.read<AdminDashboardController>();
    if (!c.canRefresh) {
      showSnack(context, 'يُسمح بتحديث الإحصائيات مرة كل دقيقة فقط', SnackKind.info);
      return;
    }
    final fromCloud = await c.refresh();
    if (!context.mounted) return;
    if (fromCloud) {
      showSnack(context, 'تم تحديث الإحصائيات');
    } else {
      showSnack(context, 'تعذر الاتصال بخدمة التحديث السحابية — تم عرض آخر بيانات محفوظة', SnackKind.info);
    }
  }

  void _redirectToLogin(BuildContext context) {
    AdminSessionService.instance.clearCache();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminDashboardController()
        ..onSessionExpired = () {
          _redirectToLogin(context);
        }
        ..load(),
      child: Consumer<AdminDashboardController>(
        builder: (context, c, _) {
          if (c.isLoading) return loadingWidget();

          return RefreshIndicator(
            onRefresh: () => _refresh(context),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('نظرة عامة', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: c.isRefreshing ? null : () => _refresh(context),
                      icon: c.isRefreshing
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      tooltip: 'تحديث الإحصائيات',
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (c.error != null) ...[
                  errorBanner(context, c.error!, onRetry: () => c.load()),
                  const SizedBox(height: 16),
                ],
                if (c.stats != null) ...[
                  _statsGrid(context, c.stats!),
                  const SizedBox(height: 24),
                  sectionTitle(context, 'آخر الحسابات المسجلة'),
                  const SizedBox(height: 8),
                  if (c.recentUsers.isEmpty)
                    emptyState(context, 'لا يوجد مستخدمون مسجلون مؤخراً')
                  else
                    _recentUsers(context, c),
                  const SizedBox(height: 24),
                  sectionTitle(context, 'آخر من استخدم التطبيق'),
                  const SizedBox(height: 8),
                  if (c.recentActiveUsers.isEmpty)
                    emptyState(context, 'لا يوجد نشاط مسجل مؤخراً')
                  else
                    _recentActiveUsers(context, c),
                ],
                if (c.stats == null && c.error == null)
                  emptyState(context, 'لم تُحسب الإحصائيات بعد'),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statsGrid(BuildContext context, DashboardStats s) {
    return LayoutBuilder(builder: (context, constraints) {
      final cross = constraints.maxWidth > 900 ? 4 : (constraints.maxWidth > 500 ? 2 : 1);
      return GridView.count(
        crossAxisCount: cross,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: [
          StatCard(label: 'إجمالي المستخدمين', value: s.totalUsers.toString(), icon: Icons.people_alt_outlined, color: Colors.indigo),
          StatCard(label: 'عدد الأعمال على التطبيق', value: s.totalBusinesses.toString(), icon: Icons.business_center_outlined, color: Colors.teal),
          StatCard(label: 'عدد العمال الموجودين', value: s.totalWorkers.toString(), icon: Icons.engineering_outlined, color: Colors.amber.shade800),
          StatCard(label: 'أعمال قيد التنفيذ', value: s.inProgressBusinesses.toString(), icon: Icons.hourglass_top, color: Colors.orange),
          StatCard(label: 'أعمال مكتملة', value: s.completedBusinesses.toString(), icon: Icons.check_circle_outline, color: Colors.green.shade700),
          StatCard(label: 'مستخدمون نشطون (7/30 يوم)', value: '${s.activeUsers7} / ${s.activeUsers30}', icon: Icons.verified_user_outlined, color: Colors.green),
          StatCard(label: 'مستخدمون جدد (7/30 يوم)', value: '${s.newUsers7} / ${s.newUsers30}', icon: Icons.person_add_alt, color: Colors.blue),
          StatCard(label: 'آخر تحديث للإحصائيات', value: formatDate(s.statsUpdatedAt), icon: Icons.schedule, color: Colors.purple),
        ],
      );
    });
  }

  Widget _recentUsers(BuildContext context, AdminDashboardController c) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final u in c.recentUsers)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  u.fullName.isNotEmpty ? u.fullName.substring(0, 1) : '؟',
                  style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.email, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _statusChip(context, u),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'تاريخ التسجيل: ${formatDate(u.createdAt)}',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${c.businessCountOf(u.uid)} أعمال', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(u.roleLabel, style: TextStyle(fontSize: 11, color: scheme.primary)),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserDetailsScreen(user: u, controller: AdminUsersController()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _recentActiveUsers(BuildContext context, AdminDashboardController c) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          for (final u in c.recentActiveUsers)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.shade100,
                child: Icon(Icons.flash_on, color: Colors.green.shade800, size: 20),
              ),
              title: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(u.email, style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 12, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'آخر استخدام: ${formatDate(u.lastActivityAt ?? u.lastLoginAt)}',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (u.appVersion.isNotEmpty && u.appVersion != '-')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('v${u.appVersion}', style: TextStyle(fontSize: 11, color: scheme.onSecondaryContainer)),
                    ),
                  const SizedBox(height: 4),
                  Text(u.lastLoginMethod.isNotEmpty && u.lastLoginMethod != '-' ? u.lastLoginMethod : 'تطبيق الجوال',
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                ],
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => UserDetailsScreen(user: u, controller: AdminUsersController()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusChip(BuildContext context, UserSnapshot u) {
    final blocked = u.isBlocked;
    final color = blocked ? Colors.red.shade600 : Colors.green.shade600;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 4),
          Text(
            blocked ? 'موقوف' : 'نشط',
            style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}