# 🏗️ بنية التطبيق — Architecture: تسهيل (Tasahel)

> توثيق البنية الحالية لمشروع `fkra` (Flutter) بعد إعادة الهيكلة التدريجية من
> نمط MVC إلى **معماريّة طبقات (Layered) مع ميزات مستقلة (Feature-Based)**.
>
> مبدأ إلزامي في كل ما كتب أدناه: **الحفاظ على سلوك التطبيق كما هو حرفياً** —
> الواجهات والنصوص والأخطاء والتخزين المحلي (Offline-First) والمزامنة والصلاحيات.

---

## 1. خلاصة إعادة الهيكلة

- بدأ المشروع **MVC**: `view/` (شاشات) ← `controller/` (`ChangeNotifier` + `Provider`) ← `model/` (نماذج تخلط SQLite + Firestore).
- أُعيدت هيكلته **على مراحل (Phases)** مع تشغيل `flutter analyze` + `flutter test` بعد كل مرحلة، **دون تغيير سلوك واحد**:
  - **Phase 0-1**: خط الأساس + بنية `core/`.
  - **Phase 2**: `features/auth` (المصادقة).
  - **Phase 3**: `features/business` (الأعمال + الحقول المخصصة).
  - **Phase 4**: `features/workers` (العمال).
  - **Phase 5**: `features/expenses` (المصروفات).
  - **Phase 6**: `features/dashboard` (الرئيسية + التقارير) وتجميع مفاتيح الجلسة.
  - **Phase 7**: `features/settings` (الإعدادات) + `features/account` (إنشاء الحساب).
  - **Phase 8**: تنظيف طبقة العرض — **Controllers خالية من أي استدعاء/استيراد Firebase**.
- **النتيجة**: `flutter analyze` = **0 errors / 0 warnings / 111 info** (كلها أسلوبية)، و`flutter test` = **11/11 ✓**.

---

## 2. القرار المعماري: "Mid-way Architecture"

لم تُفرَض **Entities صارمة** على كل البيانات لأن متصلّي المشروع يعتمدون على
خرائط `Map<String, dynamic>` في كل مكان (موجودة في ~20 ملفاً). القرار المتّخذ:

1. **طبقة بيانات كاملة** لكل ميزة: `RemoteDataSource` (كل Firebase) +
   `LocalDataSource` (SQLite/SharedPreferences) + `RepositoryImpl` (التنسيق).
2. **عقود `Repository`** تعرّف البيانات **بالخرائط** حيث لا يجدى كيان، وبـ
   Entities خفيفة حيث يعطي قيمة (مثل `AuthSession`، `LocalDashboardData`).
3. **Entities خالصة**: `AuthSession` لا يستورد Firebase؛ `LocalDashboardData`
   مجرّد `typedef` مركّب.
4. تسويات موثّقة: `AccountRepository.createAccountWithEmailPassword` يرجع
   `UserCredential` لأن `AccountController` بحاجة للـ `uid` و`updateDisplayName`
   (تعليق في العقد يشرح السبب).

---

## 3. شجرة المشروع داخل `lib/`

```
lib/
├── main.dart
├── core/                       # بنية مشتركة بين كل الميزات
│   ├── constants/app_constants.dart    # ⚠️ عقد التخزين (مفاتيح/جداول/حقول)
│   ├── errors/failures.dart
│   ├── network/connectivity_service.dart
│   ├── shared/widgets/        # app_feedback / permission_guard
│   └── utils/formatters.dart
├── db/database_helper.dart     # SQLite الموحّد (singleton) — كل الـ LocalDataSource تمرّ منه
├── features/                   # الميزات المستقلة (Layers داخل كل ميزة)
│   ├── account/  auth/  business/  dashboard/  expenses/  settings/  workers/
├── model/                      # ❗ Facades للتوافق العكسي (انظر §5)
│   ├── login_model.dart  business_model.dart  workers_model.dart
│   ├── expense_model.dart  home_model.dart  report_model.dart
│   └── settings_model.dart  account_model.dart  team_member_model.dart
├── controller/                 # ChangeNotifier + Provider (لا يلمس Firebase بعد الآن)
├── view/ + view/widgets/       # الشاشات (لم تُعدَّ بعد)
├── services/                   # ملقّطات العضوية/الإشعارات/التحليلات (تبقى كما هي)
└── admin/                      # واجهة الإدارة المستقلة + أدواتها
```

### 3.1 النمط الداخلي لكل ميزة

```
features/<feature>/
├── domain/
│   ├── entities/               # (اختياري) كيانات نقية
│   └── repositories/<x>_repository.dart    # العقد (abstract)
└── data/
    ├── datasources/
    │   ├── <x>_remote_datasource.dart      # كل اتصالات Firebase
    │   └── <x>_local_datasource.dart       # SQLite/SharedPreferences/JSON migration
    ├── models/                 # (اختياري) عوامل تطبيع/ترميز
    └── repositories/<x>_repository_impl.dart  # تنسيق المزامنة والسلوك
```

---

## 4. سجل الميزات

| الميزة | العقد (domain) | مصدر بعيد | مصدر محلي | التنفيذ | النموذج القديم |
|---|---|---|---|---|---|
| المصادقة | `auth_repository.dart` + كيان `AuthSession` | `auth_remote_datasource.dart` (Auth + users doc + Google + signOut) | `auth_local_datasource.dart` (الجلسة + pending_logins) | `auth_repository_impl.dart` | `login_model.dart` |
| الأعمال | `business_repository.dart` | `business_remote_datasource.dart` | `business_local_datasource.dart` + `custom_field_codec.dart` | `business_repository_impl.dart` (مزامنة دمج + scoped) | `business_model.dart` |
| العمال | `worker_repository.dart` | `worker_remote_datasource.dart` | `worker_local_datasource.dart` + `worker_normalizer.dart` | `worker_repository_impl.dart` (حارس scoped: لا كتابة/لا last-sync) | `workers_model.dart` |
| المصروفات | `expense_repository.dart` | `expense_remote_datasource.dart` | `expense_local_datasource.dart` | `expense_repository_impl.dart` | `expense_model.dart` |
| الرئيسية + التقارير | `dashboard_repository.dart` + `LocalDashboardData` | `dashboard_remote_datasource.dart` | `dashboard_local_datasource.dart` (يقرأ 3 جداول مرة واحدة) | `dashboard_repository_impl.dart` (home متسامح / report صارم) | `home_model.dart` + `report_model.dart` |
| الإعدادات | `settings_repository.dart` | `settings_remote_datasource.dart` (user doc + custom_fields + كلمة المرور) | `settings_local_datasource.dart` (ترحيل + معلّقات + propagate + clearAll) | `settings_repository_impl.dart` | `settings_model.dart` |
| إنشاء الحساب | `account_repository.dart` | `account_remote_datasource.dart` (Auth + users/{uid}) | `account_local_datasource.dart` (pending_accounts) | `account_repository_impl.dart` (حلقة المزامنة) | `account_model.dart` |

ملاحظات التوافق داخل التنفيذات:
- **expenses**: يُحافظ على مفتاح `last_sync_$userId` **البسيط** (بدون `expenses_`)
  — تغييره يعني إعادة تنزيل كل المصروفات. موثّق في `expense_repository_impl.dart`.
- **business**: `cache_owner_full_<uid>` علم اكتمال كاش المالك لا تلمسه الجلسات
  المقيّدة؛ رفع الحقول بالـ `whereIn` بمجموعات (30).
- **workers**: في وضع scoped **لا** تُكتب القاعدة المحلية **ولا** يتقدّم
  `last_sync` — حماية لعزل بيانات المالك.

---

## 5. نمط الـ Facade في `lib/model/`

لكي لا يتغيّر أي نبضة سلوك لدى المئات من المتصلين القائمين، بقيت الموديلات
القديمة بنفس أسماء الكلاسات ونفس كل الطرق، وأصبحت **واجهات تخويل رفيعة**:

```dart
class SettingsModel {
  final String userId;
  final SettingsRepository _repo;
  SettingsModel({required this.userId})
      : _repo = SettingsRepositoryImpl(userId: userId);

  Future<void> initStorage() => _repo.initStorage();
  // ... كل الطرق مجرد تمرير
}
```

- **لا يوجد أي منطق Firebase/SQLite بعد الآن داخل أي Facade** سوى الاستثناءات
  الثابتة المعتمدة: `hasInternet()` (خدمة موحّدة) و`signOut()` (تفويض لطبقة auth).
- **متصلو الـ Facades لم يتغيّروا**: الـ Controllers والـ Views تستدعي نفس
  الأسماء والتوقيعات.

---

## 6. البنية المشتركة `core/`

- **`constants/app_constants.dart`** — المركز الوحيد لكل عقد التخزين:
  - `PrefKeys`: مفاتيح SharedPreferences (الجلسة، pending، last_sync، الكاش…).
  - `LocalTables`: `businesses / transactions / expenses / workers / custom_fields / app_cache`.
  - `CacheKeys`: `member_profile / team_members_cache / user_profile`.
  - `FirestoreCollections` + `FirestoreFields` + `RecordStatus`.
  - ⚠️ **لا تغيّر أي قيمة**: هي عقد التخزين الحالي.
- **`network/connectivity_service.dart`** — `hasInternet()` الموحّد (حلّ محل
  التكرار في 9 نماذج).
- **`errors/failures.dart`** — أنواع الأخطاء.
- **`utils/formatters.dart`** — تنسيق الأرقام/التواريخ (عربي).
- **`shared/widgets/`** — `AppFeedback` و`PermissionGuard` (تجربة مستخدم موحّدة).

`db/database_helper.dart` — قاعدة SQLite الموحّدة (singleton) مع:
- الترحيب التلقائي من JSON القديم (idempotent وآمن) عبر
  `migrateJsonFile` / `migrateCustomFieldsJsonFile` / `migrateJsonToCache`.
- عزل كل صف بعمود `user_id` (اختبار مخصص يتحقق منه).
- استراتيجية `clearUserData`: يمسح كاش **المستخدم + الحقول المخصصة فقط**
  ويُبقي الأعمال/الحركات/المصروفات/العمال (مطابق للسلوك القديم).

---

## 7. ما زال خارج الميزات (حدود متروكة بوعي — عمل مستقبلي)

هذه المناطق ما زالت تحمل منطق Firebase مباشرةً ضمن `lib/`، وليست ضمن الميزات
المُعاد بناؤها بعد:

1. **`model/team_member_model.dart`** — إدارة أعضاء الفريق (يخلط Firestore مع
   منطق صفوف كبيرة)؛ جزء من منطقها مكرر في `services/member_api_fallback.dart`.
2. **`services/`** — `member_api.dart` (دوال السحابة)، `member_api_fallback.dart`
   (بديل محلي)، `member_session_service.dart`، `activity_service.dart`،
   `analytics_service.dart`، `fcm_token_service.dart`.
3. **`admin/**`** — واجهة الإدارة المستقلة وقوّاتها
   (`admin_firestore_service.dart`, `admin_session_service.dart`,
   `admin_api.dart`, `firebase_usage_tracker.dart`, `admin/controllers/*`).
4. **بعض الـ Views** ما زالت تقرأ `FirebaseAuth.instance.currentUser` مباشرةً
   (`splash_screen.dart`, `business_details_view.dart`,
   `member_settings_view.dart`, `change_temporary_password_view.dart`).

> الهدف المتبقي: نقل #1/#4 لاحقاً بنفس منهجية المراحل، ويبقى #2/#3 كما هما
> حتى تُقرَّر ميزانية العمل.

---

## 8. حفظ عقد التخزين (إجباري)

عند أي تعديل مستقبلي:

- **لا** تُغيّر مفاتيح SharedPreferences (`'pending_*'`, `'last_sync*'`, …).
- **لا** تُغيّر أسماء الجداول/الأعمدة في SQLite أو `key` داخل `app_cache`.
- **لا** تُغيّر أسماء مجموعات/حقول Firestore أو قيم `status`
  (`active/pending/deleted/blocked/suspended`).
- **لا** تُغيّر سلوك الطباعة داخل الـ datasources (تحمل رسائل الأخطاء القديمة).

اضبط أي قيمة جديدة عبر `AppConstants` — لا Magic Strings جديدة.

---

## 9. قواعد العمل على الكود

1. المنطق الجديد للبيانات يوضع حصراً في `features/<x>/data/*` — **الطبقة العرض
   (Controllers/Views) لا تستدعي Firebase أبداً**.
2. السلوك الموجود **يُنسخ حرفياً** (رسائل، أخطاء، تواقيت، مزامنة); أي تحسين
   يُوثَّق في تعليق `// ملاحظة معمارية` أو داخل ملف المرحلة.
3. بعد كل تغيير: `flutter analyze` و`flutter test` (المجموعة في
   `test/database_helper_test.dart` — 11 اختباراً).
4. لا إضافة مكتبات جديدة دون ضرورة؛ `Provider` يبقى آلية إدارة الحالة.

---

## 10. فحص الحالة الحالية

```bash
flutter analyze   # متوقع: 0 errors / 0 warnings / 111 info (أسلوبية فقط)
flutter test      # متوقع: All tests passed (11/11)
```

وثائق مرتبطة: `TASAHEL_DOCUMENTATION.md` (سلوك المستخدم)،
`FIREBASE_USAGE_DOCUMENTATION.md` + `FIREBASE_USAGE_TEST_PLAN.md` (استهلاك
Cloud Firestore/دوال السحابة)، `functions/FIREBASE_USAGE_BACKEND.md`.