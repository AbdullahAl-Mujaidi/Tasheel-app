// lib/admin/models/admin_role.dart

enum AdminRole {
  superAdmin('super_admin', 'مدير عام'),
  admin('admin', 'مدير'),
  analyst('analyst', 'محلل');

  const AdminRole(this.key, this.label);

  final String key;
  final String label;

  static AdminRole? tryParse(dynamic value) {
    if (value == null) return null;
    for (final role in AdminRole.values) {
      if (role.key == value.toString()) return role;
    }
    return null;
  }
}