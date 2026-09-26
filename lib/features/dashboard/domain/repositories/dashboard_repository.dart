// lib/features/dashboard/domain/repositories/dashboard_repository.dart
// عقد بيانات لوحة البداية (الصفحة الرئيسية) والتقارير.
// يجمع العمليات المشتركة بينهما (قراءة الجداول الموحدة + كاش الإحصائيات)
// في واجهة واحدة دون تكرار، مع الحفاظ على اختلافات السلوك الأصلي بين
// الصفحتين (مثلاً: تسامح Home مع فشل قراءة مجموعة مقابل صرامة Report).
import '../entities/local_dashboard_data.dart';

abstract class DashboardRepository {
  // ========== ترحيل الكاش القديم ==========
  Future<void> initHomeStorage(String userId);

  Future<void> initReportStorage(String userId);

  // ========== قراءة الجداول الموحدة (مصروفات + أعمال + عمال) ==========
  Future<LocalDashboardData> loadLocalData(String userId);

  // ========== إحصائيات كاش التطبيق ==========
  Future<Map<String, dynamic>> loadStats(String userId, String cacheKey);

  Future<void> saveStats(
      String userId, String cacheKey, Map<String, dynamic> stats);

  Future<List<Map<String, dynamic>>> loadCacheList(String userId, String cacheKey);

  Future<void> saveCacheList(
      String userId, String cacheKey, List<Map<String, dynamic>> list);

  // ========== الجلب من السحاب ==========
  /// سلوك الصفحة الرئيسية: جلب كل مجموعة على حدة بتسامح — فشل مجموعة
  /// (مثل المصروفات/العمال لتابع بلا صلاحية) لا يُسقط بقية الإحصائيات.
  Future<Map<String, dynamic>> fetchHomeStatsFromFirestore(String userId);

  /// سلوك التقارير: جلب المجموعات الثلاث معاً (Future.wait) — فشل أي منها
  /// يرفع/يُعاد رميه كما كان، مع تعيين القوائم المحلية بالحقول الفرعية نفسها.
  Future<LocalDashboardData> fetchReportDataFromFirestore(String userId);
}