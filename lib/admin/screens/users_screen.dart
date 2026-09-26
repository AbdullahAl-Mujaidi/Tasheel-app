// lib/admin/screens/users_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/admin_users_controller.dart';
import '../models/admin_models.dart';
import '../widgets/common.dart';
import 'user_details_screen.dart';

class AdminUsersScreen extends StatelessWidget {
  const AdminUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminUsersController()..load(),
      child: Consumer<AdminUsersController>(
        builder: (context, c, _) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('المستخدمون', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      onChanged: (v) => c.query = v,
                      decoration: InputDecoration(
                        hintText: 'بحث بالاسم أو البريد أو UID...',
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: c.isLoading
                    ? loadingWidget()
                    : c.error != null
                        ? errorBanner(context, c.error!, onRetry: c.load)
                        : _usersList(context, c),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _usersList(BuildContext context, AdminUsersController c) {
    if (c.users.isEmpty) {
      return emptyState(context, 'لا يوجد مستخدمون بعد');
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) {
          c.loadMore();
        }
        return false;
      },
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: c.users.length + (c.isLoadingMore ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= c.users.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          return _userTile(context, c, c.users[index]);
        },
      ),
    );
  }

  Widget _userTile(BuildContext context, AdminUsersController c, UserSnapshot u) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(child: Text(u.fullName.isNotEmpty ? u.fullName.substring(0, 1) : '؟')),
        title: Row(
          children: [
            Flexible(child: Text(u.fullName, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
            if (u.isAdmin) ...[
              const SizedBox(width: 6),
              Icon(Icons.admin_panel_settings, size: 16, color: scheme.primary),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(u.email),
            const SizedBox(height: 4),
            Row(
              children: [
                _statusChip(context, u),
                const SizedBox(width: 8),
                Text(u.roleLabel, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'سجّل منذ ${formatTodayOnly(u.createdAt)} • ${c.businessCountOf(u.uid)} أعمال • آخر نشاط ${daysAgo(u.lastActivityAt)}',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        trailing: const Icon(Icons.chevron_left),
        onTap: () async {
          final action = await Navigator.of(context).push<String>(
            MaterialPageRoute(
              builder: (_) => UserDetailsScreen(user: u, controller: c),
            ),
          );
          if (!context.mounted) return;
          switch (action) {
            case 'promoted':
              showSnack(context, 'تمت ترقية المستخدم إلى مدير');
            case 'demoted':
              showSnack(context, 'تم إلغاء صلاحية المدير');
            case 'blocked':
              showSnack(context, 'تم إيقاف الحساب');
            case 'unblocked':
              showSnack(context, 'تم إعادة تفعيل الحساب');
            case 'deleted':
              showSnack(context, 'تم حذف الحساب نهائياً');
          }
          if (action != null) c.load();
        },
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