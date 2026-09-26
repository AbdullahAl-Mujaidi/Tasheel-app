// lib/core/constants/app_constants.dart
// مركز موحّد لكل مفاتيح التخزين وأسماء Collections/Fields الثابتة.
//
// كانت هذه القيم في السابق نصوصاً مبعثرة (magic strings) في ~20 ملفاً،
// وأي تغيير مستقبلي في اسم حقل Firestore أو مفتاح SharedPreferences يعني
// البحث في كل المشروع. هذا الملف يثبتها في مكان واحد فقط.
//
// ⚠️ لا تغيّر أي قيمة هنا: هي عقد التخزين الحالي الذي لا يجوز كسره
// (Firestore/JSON/SQLite/SharedPreferences).

/// مفاتيح SharedPreferences.
class PrefKeys {
  PrefKeys._();

  static const String userId = 'user_id';
  static const String isLoggedIn = 'is_logged_in';
  static const String userEmail = 'user_email';
  static const String loginTime = 'login_time';
  static const String loggedInUser = 'logged_in_user';
  static const String pendingLogins = 'pending_logins';
  static const String pendingAccounts = 'pending_accounts';
  static const String sessionOwnerUid = 'session_owner_uid';
  static const String sessionMemberUid = 'session_member_uid';

  /// مفتاح مؤشر آخر مزامنة لكل جدول/مستخدم
  /// (النمط القديم: `last_sync_<table>_<userId>` — يُحافظ عليه كما هو).
  static String lastSync(String table, String userId) =>
      'last_sync_${table}_$userId';

  /// علم إثبات اكتمال كاش صاحب الحساب (لا تلمسه الجلسات المقيّدة أبداً).
  static String ownerCacheFull(String userId) => 'cache_owner_full_$userId';

  /// كاش الحقول المخصصة لكل مستخدم.
  static String customFields(String userId) => 'custom_fields_$userId';

  /// كاش التحديثات المعلقة لبيانات المستخدم.
  static String pendingUpdates(String userId) => 'pending_updates_$userId';

  /// عمليات الحقول المخصصة المعلقة (إضافة/تعديل/حذف) قبل رفعها للسحاب.
  static String pendingCustomFieldOps(String userId) =>
      'pending_custom_field_ops_$userId';

  /// كاش إحصائيات لوحة التحكم.
  static String cachedStats(String userId) => 'cached_stats_$userId';

  /// كاش أهم المصروفات.
  static String cachedTopExpenses(String userId) => 'cached_top_expenses_$userId';

  /// كاش حالة الأعمال.
  static String cachedBusinessStatus(String userId) =>
      'cached_business_status_$userId';

  /// قائمة الأعمال المعلقة للرفع.
  static String pendingBusinesses(String userId) => 'pending_businesses_$userId';

  /// قائمة المصروفات المعلقة للرفع.
  static String pendingExpenses(String userId) => 'pending_expenses_$userId';

  /// مفتاح آخر مزامنة البسيط `last_sync_$userId` (يُمسح عند تسجيل الخروج؛
  /// ⚠️ نفس المفتاح الذي يعتمد عليه جدول المصروفات — لا تُغيّره).
  static String lastSyncBare(String userId) => 'last_sync_$userId';
}

/// أسماء جداول SQLite المحلية (same as JSON القديمة).
class LocalTables {
  LocalTables._();

  static const String businesses = 'businesses';
  static const String transactions = 'transactions';
  static const String expenses = 'expenses';
  static const String workers = 'workers';
  static const String customFields = 'custom_fields';
  static const String appCache = 'app_cache';
}

/// مفاتيح السجلات داخل جدول app_cache في SQLite.
class CacheKeys {
  CacheKeys._();

  static const String memberProfile = 'member_profile';
  static const String teamMembersCache = 'team_members_cache';
  static const String userProfile = 'user_profile';
}

/// أسماء مجموعات Firestore.
class FirestoreCollections {
  FirestoreCollections._();

  static const String users = 'users';
  static const String teamMembers = 'team_members';
  static const String memberInvites = 'member_invites';
  static const String memberLookups = 'member_lookups';
  static const String devices = 'devices';
  static const String adminUsers = 'admin_users';

  // مجموعات فرعية تحت users/{uid}
  static const String businesses = 'businesses';
  static const String workers = 'workers';
  static const String expenses = 'expenses';
  static const String transactions = 'transactions';
  static const String customFields = 'custom_fields';
}

/// أسماء الحقول الثابتة (Firestore + JSON + SQLite معاً).
class FirestoreFields {
  FirestoreFields._();

  static const String id = 'id';
  static const String uid = 'uid';
  static const String name = 'name';
  static const String email = 'email';
  static const String date = 'date';
  static const String status = 'status';
  static const String role = 'role';
  static const String ownerUid = 'ownerUid';
  static const String ownerName = 'ownerName';
  static const String permissions = 'permissions';
  static const String scopedIds = 'scopedIds';
  static const String mustChangePassword = 'mustChangePassword';
  static const String userType = 'userType';
  static const String synced = 'synced';
  static const String createdAt = 'createdAt';
  static const String updatedAt = 'updatedAt';
}

/// قيم status المتعاقد عليها في Firestore.
class RecordStatus {
  RecordStatus._();

  static const String active = 'active';
  static const String pending = 'pending';
  static const String deleted = 'deleted';
  static const String blocked = 'blocked';
  static const String suspended = 'suspended';
  static const String subUser = 'sub_user';
  static const String superAdmin = 'super_admin';
  static const String admin = 'admin';
}