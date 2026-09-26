// lib/features/dashboard/domain/entities/local_dashboard_data.dart
// حزمة بيانات لوحة البداية/التقارير: المصروفات، الأعمال، العمال
// المقروءة من القاعدة الموحدة (SQLite) أو المجلوبة من السحاب.
typedef LocalDashboardData = ({
  List<Map<String, dynamic>> expenses,
  List<Map<String, dynamic>> businesses,
  List<Map<String, dynamic>> workers,
});