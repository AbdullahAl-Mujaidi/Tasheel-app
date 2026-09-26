// lib/admin/admin_portal.dart
import 'package:flutter/material.dart';

import '../model/login_model.dart';
import 'models/admin_role.dart';
import 'services/admin_session_service.dart';
import '../view/login_view.dart';
import 'screens/admins_screen.dart';
import 'screens/analytics_screen.dart';
import 'screens/app_versions_screen.dart';
import 'screens/audit_logs_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/firebase_usage_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/platform_settings_screen.dart';
import 'screens/sync_status_screen.dart';
import 'screens/users_screen.dart';

class AdminPortal extends StatefulWidget {
  final AdminRole role;
  final String uid;

  const AdminPortal({super.key, required this.role, required this.uid});

  @override
  State<AdminPortal> createState() => _AdminPortalState();
}

class _Section {
  final String key;
  final String title;
  final IconData icon;
  final Widget screen;

  const _Section(this.key, this.title, this.icon, this.screen);
}

class _AdminPortalState extends State<AdminPortal> {
  late final List<_Section> _sections;
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    final s = AdminSessionService.instance;
    _sections = [
      if (s.canAccessSection('dashboard'))
        _Section('dashboard', 'نظرة عامة', Icons.dashboard_outlined, const AdminDashboardScreen()),
      if (s.canAccessSection('users'))
        _Section('users', 'المستخدمون', Icons.people_alt_outlined, const AdminUsersScreen()),
      if (s.canAccessSection('analytics'))
        _Section('analytics', 'التحليلات', Icons.insights_outlined, const AdminAnalyticsScreen()),
      if (s.canAccessSection('usage'))
        _Section('usage', 'استهلاك Firebase', Icons.data_usage_outlined, const AdminFirebaseUsageScreen()),
      if (s.canAccessSection('notifications'))
        _Section('notifications', 'الإشعارات', Icons.notifications_outlined, const AdminNotificationsScreen()),
      if (s.canAccessSection('sync'))
        _Section('sync', 'حالة المزامنة', Icons.sync_outlined, const AdminSyncStatusScreen()),
      if (s.canAccessSection('versions'))
        _Section('versions', 'إصدارات التطبيق', Icons.update_outlined, const AdminAppVersionsScreen()),
      if (s.canAccessSection('admins'))
        _Section('admins', 'المديرون والصلاحيات', Icons.admin_panel_settings_outlined, const AdminAdminsScreen()),
      if (s.canAccessSection('audit'))
        _Section('audit', 'سجل العمليات', Icons.receipt_long_outlined, const AdminAuditLogsScreen()),
      if (s.canAccessSection('settings'))
        _Section('settings', 'إعدادات المنصة', Icons.settings_outlined, const AdminPlatformSettingsScreen()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final drawer = NavigationDrawer(
      selectedIndex: _selected,
      onDestinationSelected: (i) {
        if (i < _sections.length) {
          setState(() => _selected = i);
        } else {
          _logout(context);
        }
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: scheme.primary),
                  const SizedBox(width: 8),
                  Text('لوحة إدارة تسهيل', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              Text(widget.role.label, style: TextStyle(color: scheme.primary, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < _sections.length; i++)
          NavigationDrawerDestination(
            icon: Icon(_sections[i].icon),
            label: Text(_sections[i].title),
          ),
        const SizedBox(height: 8),
        const Divider(),
        NavigationDrawerDestination(
          icon: const Icon(Icons.logout),
          label: const Text('تسجيل الخروج'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_sections[_selected].title),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'تسجيل الخروج',
            onPressed: () => _logout(context),
          ),
        ],
      ),
      drawer: drawer,
      body: _sections[_selected].screen,
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل تريد تسجيل الخروج من لوحة المدير؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تسجيل الخروج')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await LoginModel().signOut();
    AdminSessionService.instance.clearCache();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }
}