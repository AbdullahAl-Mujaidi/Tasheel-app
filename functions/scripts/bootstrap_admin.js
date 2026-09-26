/**
 * سكربت Bootstrap لتجهيز الحساب الإداري الأساسي (Super Admin).
 *
 * طريقة الاستخدام الآمنة:
 * 1. تأكد من وجود ملف Service Account لديك (من Firebase Console → إعدادات المشروع
 *    → حسابات الخدمة → إنشاء مفتاح خاص جديد). لا يُرفع هذا الملف إلى المستودع أبداً.
 * 2. عيّن متغير بيئة GOOGLE_APPLICATION_CREDENTIALS إلى مسار الملف، ثم شغّل:
 *      GOOGLE_APPLICATION_CREDENTIALS="C:/path/serviceAccount.json" npm run bootstrap
 *    أو على Windows PowerShell:
 *      $env:GOOGLE_APPLICATION_CREDENTIALS="C:/path/serviceAccount.json"
 *      npm run bootstrap
 * 3. يمكن تمرير بريد آخر عبر وسيط:
 *      npm run bootstrap -- abdullahalmjudi@gmail.com
 *
 * ملاحظة: إذا كان البريد غير موجود في Firebase Authentication، أنشئه أولاً من
 * Firebase Console (Authentication → Add user) ثم أعد تشغيل السكربت. لا ننشئ
 * كلمة مرور عشوائية داخل الكود لأسباب أمنية.
 */
const admin = require('firebase-admin');

// لا نقرأ أي بيانات سرية من كود التطبيق. المفتاح يأتي من البيئة فقط.
admin.initializeApp();

const DEFAULT_EMAIL = 'abdullahalmjudi@gmail.com';

async function main() {
  const email = (process.argv.slice(2)[0] || DEFAULT_EMAIL).toLowerCase().trim();

  console.log('=== Bootstrap Super Admin ===');
  console.log('البريد:', email);

  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
  } catch (e) {
    console.error(
      '\n❌ الحساب غير موجود في Firebase Authentication.\n' +
        'أنشئه أولاً يدوياً من Firebase Console (Authentication → Add user)\n' +
        'ثم أعد تشغيل هذا السكربت، أو استخدم تطبيق تسجيل المستخدمين الحالي.\n' +
        '(لا ننشئ كلمة مرور عشوائية داخل الكود لأسباب أمنية)'
    );
    process.exit(1);
  }

  // 1) تثبيت Custom Claim (source of truth للتفويض في Firestore Rules)
  await admin.auth().setCustomUserClaims(user.uid, { role: 'super_admin' });

  // 2) وثيقة إدارة في admin_users مع علامة محمية
  const db = admin.firestore();
  await db.collection('admin_users').doc(user.uid).set(
    {
      uid: user.uid,
      email: email,
      displayName: user.displayName || email,
      role: 'super_admin',
      status: 'active',
      protected: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  console.log(`\n✅ تم تعيين ${email} كـ Super Admin`);
  console.log('   UID:', user.uid);
  console.log('   الدور: super_admin');
  console.log('   الحماية: مُفعّلة (لا يمكن تقليص دوره من اللوحة)');
}

main().catch((e) => {
  console.error('فشل التنفيذ:', e.message);
  process.exit(1);
});