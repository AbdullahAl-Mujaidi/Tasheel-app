# Backend — بيانات الاستهلاك الرسمية (Google Cloud Monitoring)

هذا الملف يشرح الجزء الخلفي من نظام "استهلاك Firebase" في لوحة المدير:
كيف تعمل الدالة، ما المطلوب تفعيله في Console، وكيف تُنشر وتُختبر.

> الحالة الحالية: المشروع على خطة **Spark**. النشر يتطلب **Blaze**.
> لذلك الكود مكتوب وجاهز بالكامل، وستبقى صفحة التطبيق تعرض
> "البيانات الرسمية غير متاحة حاليًا" حتى تنشر الدالة. لا يوجد أي تغيير
> مطلوب في تطبيق Flutter بعد النشر — سيتصل تلقائيًا بالدالة فور توفرها.

---

## 1) ما الذي تم بناؤه؟

دالة واحدة قابلة للاستدعاء (Callable):

```
exports.getFirebaseUsage
```

تستدعيها لوحة المدير فقط (`AdminApi.getFirebaseUsage`) وهي:

1. **تتحقق من الصلاحية** عبر `hasRole(context, ['super_admin', 'admin', 'analyst'])`
   — أي حساب بأي دور إداري. غير الأدمن = `permission-denied`.
2. **تجلب من Google Cloud Monitoring** (بنفس المصدر الذي تستخدمه لوحة Firebase
   Console > Usage) ثلاثة مقاييس رسمية:
   - `firestore.googleapis.com/document/read_count`
   - `firestore.googleapis.com/document/write_count`
   - `firestore.googleapis.com/document/delete_count`
   بتجميع يومي (`ALIGN_SUM` + `REDUCE_SUM` بفاصل 86400 ثانية).
3. **تحسب عدد مستخدمي Authentication** عبر `admin.auth().listUsers()`
   (مجاني تمامًا، لا يستهلك قراءات Firestore).
4. **تعيد JSON نظيفًا** للعميل من دون أي أسرار.

### شكل الاستجابة

```jsonc
{
  "source": "google_cloud_monitoring",
  "usageAvailable": true,
  "fetchedAt": "2026-09-20T10:30:00.000Z",
  "authUsers": 1250,
  "firestore": {
    "today": { "reads": 1245, "writes": 320, "deletes": 15 },
    "month": { "reads": 41200, "writes": 9600, "deletes": 450 },
    "daily": [
      { "date": "2026-09-14", "reads": 900,  "writes": 210, "deletes": 9 },
      { "date": "2026-09-20", "reads": 1245, "writes": 320, "deletes": 15 }
    ]
  },
  "storage": { "available": false, "bytes": null }
}
```

حالات الفشل تُعاد بهيكل صريح وليس استثناء، ليعرض التطبيق رسالة دقيقة:

```jsonc
{ "usageAvailable": false, "errorCode": "permission_denied",
  "errorMessage": "...", "fetchedAt": "..." }
```

| `errorCode` | المعنى |
|---|---|
| `permission_denied` | دالة Monitoring لا تملك صلاحية القراءة (راجع القسم 3) |
| `api_not_enabled` | خدمة Cloud Monitoring API غير مفعّلة (راجع القسم 2) |
| `dependency_missing` | حزمة `@google-cloud/monitoring` غير مثبتة |
| `project_not_found` | لا يمكن تحديد project ID |

---

## 2) تفعيل Cloud Monitoring API

من Firebase Console → مشروع **tasheel-e4d47** → ⚙️ إعدادات المشروع → علامة التبويب
"الحسابات والخدمات" → الحسابات والخدمات → نعم، السماح بـ Cloud Monitoring
(التفعيل يظهر أحياناً كخامس تبويب **"تكاملات"** — "Integrations").

أو مباشرة من Google Cloud Console:

```
https://console.cloud.google.com/apis/library/monitoring.googleapis.com?project=tasheel-e4d47
```

زر **Enable**. لا تكلفة لتفعيله (القراءات ضمن الحصة المجانية 1 مليون time-series/شهر).

---

## 3) صلاحيات IAM (Service Account)

- Cloud Functions تعمل بحساب خدمة. أسهل طريقة (موصى بها أولاً):
  أضف الدور **Monitoring Viewer** (`roles/monitoring.viewer`) لحساب
  **App Engine default service account**:
  ```
  tasheel-e4d47@appspot.gserviceaccount.com
  ```
- للحصول على أقل صلاحية ممكنة (أفضل أمنيًا)، أنشئ حساب خدمة مخصصًا باسم
  `firebase-usage-reader` وامنحه **Monitoring Viewer** فقط، وعيّنه كحساب تشغيل
  للدالة أثناء النشر (راجع القسم 4).

**خطوات إنشاء حساب خدمة مخصص (اختياري):**

```
https://console.cloud.google.com/iam-admin/serviceaccounts?project=tasheel-e4d47
```

1. إنشاء حساب خدمة → الاسم `firebase-usage-reader`.
2. منح الدور `Monitoring Viewer` فقط (قراءة، بلا أي صلاحية كتابة).
3. هذه هي **الصلاحية الوحيدة** المطلوبة: `monitoring.timeSeries.list`.

> لا يُنزَّل ملف مفتاح (JSON) أبدًا — Cloud Functions تستخدم حساب التشغيل
> المرتبط بالمشروع تلقائيًا، فلا يوجد أي Secret خارج الـ Backend.

---

## 4) النشر (يتطلب خطة Blaze)

```bash
cd functions
npm install          # يثبّت @google-cloud/monitoring
firebase deploy --only functions:getFirebaseUsage
```

عند استخدام حساب خدمة مخصص:

```bash
gcloud functions deploy getFirebaseUsage \
  --runtime nodejs20 \
  --trigger-http \
  --allow-unauthenticated \
  --service-account firebase-usage-reader@tasheel-e4d47.iam.gserviceaccount.com \
  --region us-central1
```

> الدالة تُحمِّل `@google-cloud/monitoring` كسلاً (lazy) داخل الدالة نفسها،
> فلن تؤثر أزمة الحزمة على بقية دوال المشروع على Spark قبل النشر.

---

## 5) الاختبار والتحقق من صحة الأرقام

بعد النشر:

1. افتح صفحة "استهلاك Firebase" في لوحة المدير → يجب أن يظهر قسم
   **البيانات الرسمية** أرقامًا.
2. قارن بـ Firebase Console → Firestore → **Usage** (نفس المصدر: Monitoring).
3. **يُنصح بمراعاة التأخير الرسمي**: المقاييس تُحسب كل دقيقة وقد تأخذ
   **حتى 4 دقائق** لتظهر. الأرقام اليومية تُحسب حسب **توقيت UTC** (ليست
   بمنتصف ليل صنعاء)، لذلك قد يبدو يومك مبدوءًا عند مقارنته بالكونسول
   بفارق 3 ساعات — هذا فرق فترة زمنية وليس خطأ.
4. التطبيق يعرض دائمًا "آخر مزامنة" وليس "الاستخدام الحالي".

### حدود الدقة (رسميًا من Google)

- لوحة الاستخدام وبيانات Monitoring **تقديرية**: "Billed usage is likely higher.
  In all cases of discrepancy, the billing report takes precedence."
- أي فرق بين التطبيق والفاتورة الفعلية **متوقع وموثق** — سبب المقارنة النهائية
  هو تقرير الفوترة في Google Cloud Console، وليس لوحة الاستخدام.

---

## 6) ما غير المتاح رسميًا (لا نخترعه)

| البيانات | الحالة |
|---|---|
| Storage (حجم التخزين) | لا يوجد مقياس `timeSeries.list` رسمي لـ Native mode → الحقل `available: false`، والتطبيق يعرض رسالة صادقة |
| Network / البيانات المنقولة | لا يوجد مقياس Monitoring رسمي → يعرض "غير متاح" |
| الحدود المجانية (Quota) | ليست من الدالة؛ في ملف `QuotaLimits` داخل تطبيق Flutter (قابلة للتعديل من مكان واحد) |