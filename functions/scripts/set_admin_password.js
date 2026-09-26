/**
 * سكربت ضبط كلمة مرور الحساب الإداري.
 *
 * ينشئ الحساب إذا لم يكن موجوداً في Firebase Authentication، أو يغيّر
 * كلمة المرور إذا كان موجوداً. لا يغير الدور (شغّل bootstrap منفصلاً).
 *
 * طريقة الاستخدام الآمنة:
 * 1. عيّن متغير بيئة GOOGLE_APPLICATION_CREDENTIALS إلى مسار ملف Service Account.
 * 2.    $env:GOOGLE_APPLICATION_CREDENTIALS="C:/path/serviceAccount.json"
 *      npm run set-password -- abdullahalmjudi@gmail.com "كلمة-المرور"
 *    مثال:
 *      npm run set-password -- abdullahalmjudi@gmail.com 123456
 *
 * ملاحظة: كلمة المرور تمر كوسيط سطر أوامر؛ لا ترفع هذا الملف أو أي ملف
 * يخزنها إلى المستودع. الأفضل تنفيذها محلياً ثم مسح محفوظات الطرفية.
 */
const admin = require('firebase-admin');

admin.initializeApp();

const DEFAULT_EMAIL = 'abdullahalmjudi@gmail.com';

async function main() {
  const emailArg = (process.argv.slice(2)[0] || '').toLowerCase().trim();
  const passwordArg = process.argv.slice(2)[1] || '';

  const email = emailArg || DEFAULT_EMAIL;
  const password = passwordArg || undefined;

  if (!password) {
    console.error(
      '\n❌ لم تمرر كلمة المرور.\n' +
        'الاستخدام: npm run set-password -- <email> <password>\n' +
        'مثال: npm run set-password -- abdullahalmjudi@gmail.com "MySecret123"'
    );
    process.exit(1);
  }

  if (password.length < 6) {
    console.error('\n❌ كلمة المرور يجب ألا تقل عن 6 أحرف.');
    process.exit(1);
  }

  console.log('=== Set / Reset Admin Password ===');
  console.log('البريد:', email);

  try {
    const user = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(user.uid, { password });
    console.log(`\n✅ تم تحديث كلمة المرور للحساب ${email}`);
    console.log('   يمكنك الآن تسجيل الدخول بها من التطبيق.');
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      const created = await admin.auth().createUser({
        email,
        password,
      });
      console.log(`\n✅ تم إنشاء الحساب ${email} بكلمة المرور الجديدة.`);
      console.log('   UID:', created.uid);
      console.log('\nالتالي: شغّل bootstrap لتعيينه Super Admin:');
      console.log('   npm run bootstrap -- ' + email);
    } else {
      throw e;
    }
  }
}

main().catch((e) => {
  console.error('فشل التنفيذ:', e.message);
  process.exit(1);
});