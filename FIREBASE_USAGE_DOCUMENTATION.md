# نظام "استهلاك Firebase" — التوثيق النهائي

> المشروع: تطبيق تسهيل (Tasahel) — `tasheel-e4d47`
> هذه الصفحة المرجعية الكاملة للميزة: ما بُني، كيف يعمل، حدوده، وأين تعدَّل الحصص.

---

## 1) الهدف

قسم جديد في لوحة المدير يعرض:

1. **الاستهلاك الرسمي** لـ Firestore من نفس مصدر لوحة Firebase Console
   (Google Cloud Monitoring): قراءات + كتابات + حذف، لليوم والشهر وآخر 7/14/30 يوم.
2. **عدد مستخدمي Authentication** (التوثيق) الحالي.
3. **حصص خطة Spark** مع أشرطة نسبة ملوّنة وتنبيهات عند الاقتراب من الحد أو تجاوزه.
4. **عداد عمليات التطبيق المحلي** (اختياري، على جهاز المدير فقط، بدون أي استهلاك Firestore).

قاعدة غير قابلة للكسر: **لا نختلق أرقاماً** — أي قيمة رسمية معطلة تُعرض "غير متاحة"
مع السبب، ولا تُعرض قيمة تخمينية.

---

## 2) البنية المعمارية

```
الشاشة (Flutter)
 └─ FirebaseUsageController (ChangeNotifier)   ← التحكم + حالات التحميل/الخطأ
     └─ FirebaseUsageRepository                 ← التنسيق: شبكة | كاش SQLite | عدّاد محلي
         ├─ AdminApi.getFirebaseUsage()         ← استدعاء Cloud Function (الطبقة الآمنة)
         │     └─ getFirebaseUsage (Cloud Function) → Google Cloud Monitoring API
         ├─ app_cache (SQLite)                  ← كاش آخر بيانات رسمية ناجحة
         └─ FirebaseUsageTracker                ← عدّاد عمليات التطبيق (SQLite)
```

### الملفات

| الملف | الدور |
|---|---|
| `functions/index.js` | دالة `getFirebaseUsage` (الخادم) |
| `functions/package.json` | إضافة `@google-cloud/monitoring ^3.0.5` (v6 تتطلب Node ≥22) |
| `functions/FIREBASE_USAGE_BACKEND.md` | خطوات تفعيل API + IAM + النشر + التحقق |
| `lib/admin/models/firebase_usage_model.dart` | `FirestoreOps`, `FirestoreDailyPoint`, `OfficialFirebaseUsage`, `UsageSnapshot` |
| `lib/admin/models/firebase_usage_quota.dart` | `QuotaLimits` (مكان التعديل الوحيد), `QuotaStatus`, `UsageAlertLevel`, `QuotaAlert` |
| `lib/admin/services/firebase_usage_tracker.dart` | عدّاد عمليات التطبيق (محلي، صفر شبكة) |
| `lib/admin/services/firebase_usage_repository.dart` | التنسيق مع الكاش والتقادم |
| `lib/admin/services/admin_api.dart` | طريقة `getFirebaseUsage` |
| `lib/admin/controllers/firebase_usage_controller.dart` | المتحكم |
| `lib/admin/screens/firebase_usage_screen.dart` | الصفحة كاملة |
| `lib/admin/admin_portal.dart` | إضافة قسم "استهلاك Firebase" |
| `lib/admin/services/admin_session_service.dart` | `canAccessSection('usage')` لكل الأدمن |

---

## 3) كيف تعمل البيانات الرسمية

1. الصفحة تُرسم فوراً بآخر كاش محلي سليم (≤ 15 دقيقة) — **بلا طلب شبكة**.
2. عند تقادم الكاش أو التحديث اليدوي، تُستدعى `getFirebaseUsage`.
3. الخادم يتحقق من الدور (`super_admin/admin/analyst`) ثم يستعلم Monitoring لثلاثة
   مقاييس مثبتة، ويجمعها يومياً (فاصل 86400 ثانية، ALIGN_SUM + REDUCE_SUM) لليوم
   والشهر وآخر N يوم، ويحسب مستخدمي Auth عبر `admin.auth().listUsers()`.
4. تعود الاستجابة `{ source, usageAvailable, fetchedAt, authUsers, firestore: { today, month, daily }, storage }`
   أو `{ usageAvailable:false, errorCode, errorMessage, ... }`.
5. عند النجاح يُخزَّن كاش جديد. عند الفشل تُعرض آخر كاش مع شريط توضيحي.
6. تحديث تلقائي هادئ كل 5 دقائق أثناء فتح القسم (بلا وميض؛ لا يتصل بالشبكة
   إلا بعد تقادم الكاش).

### أكواد الأخطاء المرتجعة (لا استثناءات)

| errorCode | المعنى (وإجراء) |
|---|---|
| `permission_denied` | دور Monitoring غير ممنوح لحساب الخدمة → IAM |
| `api_not_enabled` | Monitoring API غير مفعل → Console |
| `dependency_missing` | الحزمة غير مثبتة في `functions` |
| `project_not_found` | تعذّر تحديد المشروع |
| `unknown` | خطأ غير متوقع |

---

## 4) الدقة والحدود (رسمياً من Google — لا تلوم التطبيق)

- أرقام Monitoring **تقديرية**: "تأخر حتى 4 دقائق" ويظهر ذلك في الصفحة
  ("أرقام تقديرية قد تتأخر").
- **اليوم/الشهر بتوقيت UTC** — عند مقارنة "اليوم" بمنتصف ليل صنعاء ستجد فرقاً
  زمنياً، وهذا ليس خطأ.
- عند أي اختلاف: **تُعتمد فاتورة Google (Billing Report)** وليس لوحة الاستخدام.
- **التخزين (Storage) والإنترنت**: لا مقياس Monitoring رسمي لخطة Native →
  يعرض التطبيق "غير متاح عبر الواجهة الرسمية" بدل رقم مختلق.
- النشر يتطلب خطة **Blaze** — على Spark يبقى القسم في وضع "غير متاحة" مع السبب
  وزر إعادة المحاولة، ويتصل تلقائياً فور النشر دون تعديل التطبيق.

---

## 5) الحصص — مكان التعديل الوحيد

في `lib/admin/models/firebase_usage_quota.dart` → `QuotaLimits.spark`:

| الحصة | القيمة الحالية |
|---|---|
| قراءات / يوم | 50,000 |
| كتابات / يوم | 20,000 |
| حذف / يوم | 20,000 |
| تخزين (مرجعي) | 1 GiB |
| إنترنت / شهر (مرجعي) | 10 GiB |

مستويات التنبيه: 80% (عادي) ← 90% (تحذير) ← 100% فأكثر (حرج/تجاوز).

---

## 6) الأمان

- لا يوجد أي Service Account أو مفتاح في تطبيق Flutter إطلاقاً.
- الخادم صلاحية `hasRole` قبل أي استعلام، ولوحة قواعد Firestore لم تتغير.
- عدد Auth يُحسب مجاناً (بلا قراءات Firestore).
- عمليات التطبيق تُخزَّن في SQLite فقط (صفر استهلاك شبكة/فاتورة).

---

## 7) ما لم يُلمس في التطبيق

- لم تُعدَّل أي بيانات أو شاشات أقسام لوحة المدير الأصلية.
- لم تُضف أي عمليات إلى Rules أو بنية Firestore.
- التعديلات الإطارية فقط: خانة قسم جديد + `canAccessSection`.

---

## 8) خطوات التشغيل الكاملة (تذكير سريع)

1. ترقية Blaze (ضرورية للنشر فقط).
2. `functions`: تفعيل Cloud Monitoring API + منح `Monitoring Viewer` لحساب الخدمة
   (راجع `functions/FIREBASE_USAGE_BACKEND.md`).
3. `cd functions && npm install && firebase deploy --only functions:getFirebaseUsage`.
4. فتح القسم → مقارنة الأرقام مع Console > Firestore > Usage
   (راجع خطة الاختبار المنفصلة).

---

## 9) التغييرات القادمة المحتملة

- وصل `recordRead/recordWrite/recordDelete` في نقاط العمليات الأساسية
  (يفضل أن تكون اختيارية ومعطلة افتراضياً).
- إضافة تقرير تصدير (PDF/Excel) — يُبني المستهلك على النماذج الجاهزة.