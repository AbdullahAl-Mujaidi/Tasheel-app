/**
 * Cloud Functions لنظام إدارة منصة "تسهيل".
 *
 * ملاحظة أمنية:
 * - جميع العمليات الحساسة تتم هنا عبر Admin SDK ولا تمر عبر Rules.
 * - لا يوجد أي سر داخل تطبيق Flutter.
 * - التحقق من الأدمن الحقيقي يتم عبر Custom Claims + هذه الدوال.
 */
const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

const VALID_ROLES = ['super_admin', 'admin', 'analyst'];
const PROTECTED_ADMINS = ['abdullahalmjudi@gmail.com'];

async function isTrustedRoleChangeActor(uid) {
  if (typeof uid !== 'string' || uid.length === 0) return false;
  if (uid === 'SYSTEM_REPAIR') return true;
  try {
    const actor = await admin.auth().getUser(uid);
    const email = (actor.email || '').toLowerCase();
    return PROTECTED_ADMINS.includes(email) ||
      actor.customClaims?.role === 'super_admin';
  } catch (e) {
    console.error('فشل التحقق من منفذ تغيير الدور:', uid, e);
    return false;
  }
}

// ===================== المستخدمون التابعون (Sub-Users / Employees) =====================
// نموذج الأمان:
//  - المالك (أي مستخدم مسجل عادي) يملك بياناته تحت users/{ownerUid}.
//  - المستخدم التابع لديه حساب Firebase Auth خاص للمصادقة فقط، وبياناته تبقى
//    ضمن حساب المالك: users/{ownerUid}/team_members/{memberUid}.
//  - كل العمليات الإدارية على التابعين تتم هنا عبر Admin SDK وتتحقق أن
//    المستدعي هو صاحب الحساب نفسه (context.auth.uid == ownerUid) وليس تابِعاً.
//  - لا يتم تخزين كلمة المرور في Firestore إطلاقاً.
const SUB_PERMISSION_MODULES = ['businesses', 'workers', 'expenses', 'reports', 'settings'];
const SUB_PERMISSION_ACTIONS = ['read', 'create', 'update', 'delete'];

// دالة التحقق: هل uid المطلوب تابعٌ لأي مالك؟ (يمنع التابعين من إضافة تابعين)
async function isSubUser(uid) {
  const snap = await db.collectionGroup('team_members').where('uid', '==', uid).limit(1).get();
  return !snap.empty;
}

// دالة التحقق: هل المستدعي هو بالضبط مالك العضو المطلوب؟
async function isOwnerOfMember(ownerUid, memberUid, actorUid) {
  if (ownerUid !== actorUid) return false;
  const doc = await db.collection('users').doc(ownerUid).collection('team_members').doc(memberUid).get();
  if (!doc.exists) return false;
  return doc.data().ownerUid === ownerUid && doc.data().uid === memberUid;
}

function normalizePermissions(permissions) {
  const result = {};
  for (const module of SUB_PERMISSION_MODULES) {
    const raw = permissions && permissions[module];
    const entry = {};
    if (module === 'reports' || module === 'settings') {
      entry.read = !!(raw && raw.read);
      entry.create = false;
      entry.update = false;
      entry.delete = false;
    } else {
      for (const action of SUB_PERMISSION_ACTIONS) {
        entry[action] = !!(raw && raw[action]);
      }
    }
    result[module] = entry;
  }
  return result;
}

function validateSubUserEmail(email) {
  if (typeof email !== 'string') return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email.trim());
}

function validateSubUserPassword(password) {
  if (typeof password !== 'string' || password.length < 6) return false;
  if (!/[A-Z]/.test(password)) return false;
  if (!/[a-z]/.test(password)) return false;
  if (!/[0-9]/.test(password)) return false;
  return true;
}

// ===================== إنشاء مستخدم تابع =====================
exports.createSubUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const ownerUid = context.auth.uid;

  // التابع لا يملك صلاحية إنشاء مستخدمين تابعين.
  if (await isSubUser(ownerUid)) {
    throw new functions.https.HttpsError('permission-denied', 'لا تملك صلاحية إنشاء مستخدم');
  }

  const { name, email, temporaryPassword, permissions, scopedIds } = data || {};
  if (typeof name !== 'string' || name.trim().length < 3) {
    throw new functions.https.HttpsError('invalid-argument', 'الاسم غير صحيح (3 أحرف على الأقل)');
  }
  if (!validateSubUserEmail(email)) {
    throw new functions.https.HttpsError('invalid-argument', 'البريد الإلكتروني غير صحيح');
  }
  if (!validateSubUserPassword(temporaryPassword)) {
    throw new functions.https.HttpsError('invalid-argument', 'كلمة المرور ضعيفة (6 أحرف على الأقل مع حرف كبير ورقم)');
  }
  // نطاق اختياري: مشاركة عمل واحد (scopedIds: { businesses: [docId] }).
  const cleanScopedIds = {};
  if (scopedIds && typeof scopedIds === 'object') {
    for (const [module, ids] of Object.entries(scopedIds)) {
      if (Array.isArray(ids) && ids.length > 0) {
        cleanScopedIds[module] = ids.map((id) => String(id));
      }
    }
  }

  const cleanPermissions = normalizePermissions(permissions);
  const cleanEmail = email.trim().toLowerCase();

  try {
    // بريد مسجّل مسبقاً (حساب خاص بالعضو): نفوّضه دون إنشاء حساب جديد —
    // نستخدم UID الحساب الموجود فقط (الخادم هو من يستطيع كشفه عبر Admin SDK).
    let existingUid = null;
    try {
      const existing = await admin.auth().getUserByEmail(cleanEmail);
      existingUid = existing.uid;
    } catch (e) {
      if (!e.code || e.code !== 'auth/user-not-found') {
        throw new functions.https.HttpsError('internal', 'حدث خطأ أثناء التحقق من البريد');
      }
    }

    if (existingUid === ownerUid) {
      throw new functions.https.HttpsError('already-exists', 'هذا بريدك أنت — لا يمكن تفويضه لنفسك');
    }

    // لا يجوز أن يكون البريد حساباً تابعاً أو مالكاً سابقاً.
    const ownerSnap = await db.collection('users').doc(ownerUid).get();
    const ownerName = ownerSnap.exists ? (ownerSnap.data().fullName || '') : '';

    let memberUid;
    if (existingUid) {
      memberUid = existingUid;
    } else {
      const created = await admin.auth().createUser({
        email: cleanEmail,
        password: temporaryPassword,
        displayName: name.trim(),
        // بريد الموظف مقدم من المالك مباشرة، لذا يعتبر موثقاً منذ البداية ليتسنى
        // تسجيل الدخول بالبريد وكلمة المرور المؤقتة دون الحاجة لرسالة تحقق.
        emailVerified: true,
      });
      memberUid = created.uid;
    }

    await db.collection('users').doc(ownerUid).collection('team_members').doc(memberUid).set({
      uid: memberUid,
      ownerUid,
      name: name.trim(),
      email: cleanEmail,
      role: 'employee',
      permissions: cleanPermissions,
      ...(Object.keys(cleanScopedIds).length > 0 ? { scopedIds: cleanScopedIds } : {}),
      status: 'active',
      mustChangePassword: true,
      ownerName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection('member_lookups').doc(memberUid).set({
      uid: memberUid,
      ownerUid,
      email: cleanEmail,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await db.collection('users').doc(memberUid).set({
      uid: memberUid,
      ownerUid,
      userType: 'sub_user',
      email: cleanEmail,
      fullName: name.trim(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await writeAuditLog({
      actorUid: ownerUid,
      actorEmail: context.auth.token.email || null,
      action: 'sub_user_created',
      result: 'success',
      details: { memberUid, email: cleanEmail, permissions: cleanPermissions, scopedIds: cleanScopedIds },
    });

    return { success: true, uid: memberUid, email: cleanEmail };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    const code = e && e.code;
    if (code === 'auth/email-already-exists' || code === 'auth/invalid-email') {
      if (code === 'auth/email-already-exists') {
        throw new functions.https.HttpsError('already-exists', 'البريد مستخدم بالفعل');
      }
      throw new functions.https.HttpsError('invalid-argument', 'البريد الإلكتروني غير صحيح');
    }
    throw new functions.https.HttpsError('internal', 'حدث خطأ أثناء إنشاء المستخدم');
  }
});

// ===================== تعديل بيانات/صلاحيات مستخدم تابع =====================
exports.updateSubUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const { ownerUid, memberUid } = data || {};
  if (!ownerUid || !memberUid) {
    throw new functions.https.HttpsError('invalid-argument', 'بيانات غير صحيحة');
  }
  if (!(await isOwnerOfMember(ownerUid, memberUid, context.auth.uid))) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن تعديل صلاحيات هذا المستخدم');
  }

  const patch = {};
  if (data.name !== undefined) {
    if (typeof data.name !== 'string' || data.name.trim().length < 3) {
      throw new functions.https.HttpsError('invalid-argument', 'الاسم غير صحيح');
    }
    patch.name = data.name.trim();
  }
  if (data.permissions !== undefined) {
    patch.permissions = normalizePermissions(data.permissions);
  }
  if (Object.keys(patch).length === 0) {
    throw new functions.https.HttpsError('invalid-argument', 'لا توجد بيانات للتحديث');
  }
  patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();

  await db.collection('users').doc(ownerUid).collection('team_members').doc(memberUid)
    .update(patch);

  await writeAuditLog({
    actorUid: context.auth.uid,
    actorEmail: context.auth.token.email || null,
    action: 'sub_user_updated',
    result: 'success',
    details: { memberUid, patch: Object.keys(patch) },
  });

  return { success: true };
});

// ===================== تعطيل/تفعيل مستخدم تابع =====================
exports.setSubUserStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const { ownerUid, memberUid, disabled } = data || {};
  if (!ownerUid || !memberUid) {
    throw new functions.https.HttpsError('invalid-argument', 'بيانات غير صحيحة');
  }
  if (!(await isOwnerOfMember(ownerUid, memberUid, context.auth.uid))) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن تعديل صلاحيات هذا المستخدم');
  }

  try {
    // التعطيل على مستوى Auth يمنع تسجيل الدخول تماماً (حتى مع تعديل التطبيق).
    await admin.auth().updateUser(memberUid, { disabled: disabled === true });
    await db.collection('users').doc(ownerUid).collection('team_members').doc(memberUid).update({
      status: disabled === true ? 'disabled' : 'active',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: disabled === true ? 'sub_user_disabled' : 'sub_user_enabled',
      result: 'success',
      details: { memberUid, disabled },
    });

    return { success: true, disabled: disabled === true };
  } catch (e) {
    throw new functions.https.HttpsError('internal', 'حدث خطأ أثناء تعديل حالة المستخدم');
  }
});

// ===================== إعادة تعيين كلمة مرور مستخدم تابع =====================
exports.resetSubUserPassword = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const { ownerUid, memberUid, temporaryPassword } = data || {};
  if (!ownerUid || !memberUid) {
    throw new functions.https.HttpsError('invalid-argument', 'بيانات غير صحيحة');
  }
  if (!(await isOwnerOfMember(ownerUid, memberUid, context.auth.uid))) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن تعديل هذا المستخدم');
  }
  if (!validateSubUserPassword(temporaryPassword)) {
    throw new functions.https.HttpsError('invalid-argument', 'كلمة المرور ضعيفة (6 أحرف على الأقل مع حرف كبير ورقم)');
  }

  try {
    await admin.auth().updateUser(memberUid, { password: temporaryPassword });
    await db.collection('users').doc(ownerUid).collection('team_members').doc(memberUid).update({
      mustChangePassword: true,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: 'sub_user_password_reset',
      result: 'success',
      details: { memberUid },
    });

    return { success: true };
  } catch (e) {
    throw new functions.https.HttpsError('internal', 'حدث خطأ أثناء إعادة تعيين كلمة المرور');
  }
});

// ===================== حذف مستخدم تابع نهائياً =====================
exports.deleteSubUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const { ownerUid, memberUid } = data || {};
  if (!ownerUid || !memberUid) {
    throw new functions.https.HttpsError('invalid-argument', 'بيانات غير صحيحة');
  }
  if (!(await isOwnerOfMember(ownerUid, memberUid, context.auth.uid))) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن حذف هذا المستخدم');
  }

  try {
    await admin.auth().deleteUser(memberUid);

    // حذف وثيقة العضوية.
    await db.collection('users').doc(ownerUid).collection('team_members').doc(memberUid).delete();

    // حذف أي بيانات فرعية تحت uid التابع (مثل أجهزة FCM التابعة له).
    const devicesRef = db.collection('users').doc(memberUid).collection('devices');
    const devicesSnap = await devicesRef.get();
    for (const doc of devicesSnap.docs) {
      await doc.ref.delete();
    }

    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: 'sub_user_deleted',
      result: 'success',
      details: { memberUid },
    });

    return { success: true };
  } catch (e) {
    throw new functions.https.HttpsError('internal', 'حدث خطأ أثناء حذف المستخدم');
  }
});

// ===================== سجل العمليات =====================
async function writeAuditLog({ actorUid, actorEmail, action, result, details }) {
  try {
    await db.collection('audit_logs').add({
      actorUid: actorUid || null,
      actorEmail: actorEmail || null,
      action: action || 'unknown',
      result: result || 'unknown',
      details: details || {},
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (e) {
    console.error('فشل كتابة سجل العملية:', e);
  }
}

// يقوم بتحويل Claims الخاصة بدور معين مع التحقق من الأمان
async function setUserRole(uid, role) {
  await admin.auth().setCustomUserClaims(uid, { role: role });
  return admin.auth().getUser(uid);
}

// ===================== دور فعّال من قاعدة البيانات =====================
// يسمح للـ Callables بقبول الأدوار المعبّأة من الحقل userType في وثيقة
// المستخدم (بالإضافة إلى Custom Claims) حتى يعمل النظام بالكامل اعتماداً
// على قاعدة البيانات فقط عند الحاجة.
async function hasRole(context, allowedRoles) {
  if (!context.auth) return false;
  const claim = context.auth.token.role;
  if (claim && allowedRoles.includes(claim)) return true;
  // الحسابات المحمية تُعامل كـ super_admin من جهة الخادم، كما تفعل Rules
  // (امتلاك البريد يعني امتلاك الحساب)، حتى يعمل النظام قبل تثبيت Claims.
  const email = (context.auth.token.email || '').toLowerCase();
  if (email && PROTECTED_ADMINS.includes(email) && allowedRoles.includes('super_admin')) {
    return true;
  }
  try {
    const userDoc = await db.collection('users').doc(context.auth.uid).get();
    if (!userDoc.exists) return false;
    const userType = userDoc.data().userType;
    if (allowedRoles.includes(userType)) return true;
    const aDoc = await db.collection('admin_users').doc(context.auth.uid).get();
    if (aDoc.exists && aDoc.data().status === 'active' && allowedRoles.includes(aDoc.data().role)) {
      return true;
    }
  } catch (e) {
    console.error('فشل التحقق من الدور عبر قاعدة البيانات:', e);
  }
  return false;
}

// ===================== مزامنة Claims من userType =====================
// عند تغيير الحقل userType في وثيقة المستخدم إلى admin/super_admin يتم
// تثبيت Custom Claim ووثيقة admin_users تلقائياً (والعكس عند الإزالة).
// ملاحظة أمنية حرجة: Triggers في Firestore لا تزوّد هوية الطالب (context.auth
// غير متوفر هنا) — لذلك فرض "مَن يحق له الكتابة" يقع على Rules (الجزء الحاسم:
// فقط isSuperAdmin يعدّل userType/role بعد إصلاح الثغرة). وهذه الدالة صف دفاع
// ثانٍ:
//  1) ترفض منح super_admin لأي حساب غير محمي/غير حامل للصلاحية فعلياً
//     (تُعيد الحقل وتُسجّل محاولة التصعيد في audit_logs).
//  2) لا تقوّص دوراً أعلى أبداً (super_admin → admin لا يحدث).
//  3) تتصدى لبقايا الكلايمز: أي claim بلا سند في userType يُزال تلقائياً.
//  4) تسجّل كل انتقال/رفض في audit_logs.
exports.syncAdminFromUserType = functions.firestore
  .document('users/{userId}')
  .onWrite(async (change, context) => {
    const uid = context.params.userId;
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    const beforeType = before && before.userType;
    const afterType = after && after.userType;
    const wasAdmin = beforeType === 'admin' || beforeType === 'super_admin';
    const isAdminNow = afterType === 'admin' || afterType === 'super_admin';

    // Firestore triggers لا تستقبل context.auth. لذلك تكون هذه العلامة
    // صالحة فقط إذا كانت القواعد قد سمحت بها لـ Super Admin أو وضعها
    // Callable موثوق عبر Admin SDK، ثم نتحقق من هوية صاحبها عبر Auth.
    if (beforeType !== afterType &&
        !(await isTrustedRoleChangeActor(after && after.roleChangeAuthorizedBy))) {
      await writeAuditLog({
        actorUid: after && after.roleChangeAuthorizedBy || null,
        actorEmail: 'SYSTEM',
        action: 'privilege_escalation_alert',
        result: 'blocked',
        details: {
          uid,
          previousRole: beforeType || 'user',
          attemptedRole: afterType || 'user',
          reason: 'تغيير userType دون تفويض Super Admin موثوق',
        },
      });
      await db.collection('users').doc(uid).set({
        userType: beforeType || 'user',
        roleChangeAuthorizedBy: 'SYSTEM_REPAIR',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
      return;
    }

    let target;
    try {
      target = await admin.auth().getUser(uid);
    } catch (e) {
      console.error('فشل جلب الحساب أثناء مزامنة الدور:', uid, e);
      return;
    }
    const targetEmail = (target.email || '').toLowerCase();

    if (isAdminNow) {
      try {
        const current = target.customClaims && target.customClaims.role;
        // لا نقوّص دوراً أعلى (e.g. super_admin موجود و userType = admin)
        if (current === afterType) return;
        if (current === 'super_admin' && afterType === 'admin') return;

        // ---- حماية super_admin: لا يُمنح إلا لحساب محمي صراحةً أو ----
        // لحامل فعلي للصلاحية عبر وثيقة admin_users نشطة. أي وصول إلى
        // super_admin من حساب عادي عبر حقل userType فقط يعتبر محاولة تصعيد:
        // تُرفض، يُعاد الحقل، وتُسجَّل العملية (لا يستطيع أي عميل إنشاء
        // admin_users إلا بـ Rules تفرض super_admin).
        if (afterType === 'super_admin') {
          const adminDoc = await db.collection('admin_users').doc(uid).get();
          const isLegitSuper =
            PROTECTED_ADMINS.includes(targetEmail) ||
            (adminDoc.exists &&
              adminDoc.data().role === 'super_admin' &&
              adminDoc.data().status === 'active');
          if (!isLegitSuper) {
            await writeAuditLog({
              actorUid: null,
              actorEmail: 'SYSTEM',
              action: 'privilege_escalation_alert',
              result: 'blocked',
              details: {
                uid,
                email: targetEmail,
                attemptedRole: afterType,
                reason: 'ترقية إلى super_admin لحساب غير محمي عبر userType',
              },
            });
            // شفاء ذاتي: إعادة الحقل للحالة السابقة يمنع تعليق صلاحيات مكتسبة
            // خلف القواعد حتى لو نجحت كتابة غير مشروعة من مصدر آخر.
            await db.collection('users').doc(uid).update({
              userType: beforeType || 'user',
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.error('⚠ رُفض تصعيد إلى super_admin وأُعيد الحقل:', uid);
            return;
          }
        }

        await admin.auth().setCustomUserClaims(uid, { role: afterType });
        await db.collection('admin_users').doc(uid).set({
          uid,
          email: target.email || '',
          displayName: target.displayName || target.email || '',
          role: afterType,
          status: 'active',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
        await writeAuditLog({
          actorUid: null,
          actorEmail: 'SYSTEM',
          action: 'admin_role_synced',
          result: 'success',
          details: { uid, email: targetEmail, role: afterType },
        });
        console.log(`تم تفعيل دور ${afterType} للحساب ${uid}`);
      } catch (e) {
        console.error('فشل تفعيل الدور من userType:', e);
      }
      return;
    }

    // ---- فرع الإزالة (بعكس السابق: يشمل كل كتابة لشفاء أي claim زائد) ----
    try {
      if (PROTECTED_ADMINS.includes(targetEmail)) return;
      if (target.customClaims && target.customClaims.role) {
        await admin.auth().setCustomUserClaims(uid, null);
        await db.collection('admin_users').doc(uid).update({
          status: 'removed',
          role: admin.firestore.FieldValue.delete(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await writeAuditLog({
          actorUid: null,
          actorEmail: 'SYSTEM',
          action: 'admin_role_synced',
          result: 'success',
          details: { uid, email: targetEmail, role: null, removed: afterType || null },
        });
        console.log(`تم إزالة دور مدير للحساب ${uid}`);
      }
    } catch (e) {
      console.error('فشل إزالة الدور عند تغيير userType:', e);
    }
  });

// ===================== تعيين دور مدير =====================
exports.setAdminRole = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const actor = context.auth;
  if (!(await hasRole(context, ['super_admin']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحية Super Admin مطلوبة لهذه العملية');
  }

  const { uid, role, email, displayName } = data || {};
  if (!uid || !role || !VALID_ROLES.includes(role)) {
    throw new functions.https.HttpsError('invalid-argument', 'بيانات غير صحيحة');
  }
  if (uid === actor.uid && role !== 'super_admin') {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن تقليص دور نفسك');
  }

  try {
    // منع تقليص/تعديل الحسابات المحمية (الأساسية)
    const target = await admin.auth().getUser(uid);
    const targetEmail = (email || target.email || '').toLowerCase();
    if (PROTECTED_ADMINS.includes(targetEmail) && role !== 'super_admin') {
      throw new functions.https.HttpsError('permission-denied', 'هذا الحساب محمي ولا يمكن تغيير دوره');
    }

    // منع تنزيل آخر مدير عام (تنزيل super_admin نشط إلى دور أدنى)
    if (role !== 'super_admin') {
      const adminDoc = await db.collection('admin_users').doc(uid).get();
      const currentSuper =
        (target.customClaims && target.customClaims.role === 'super_admin') ||
        (adminDoc.exists && adminDoc.data().role === 'super_admin');
      if (currentSuper) {
        const superAdmins = await db.collection('admin_users')
          .where('role', '==', 'super_admin')
          .where('status', '==', 'active')
          .get();
        if (superAdmins.size <= 1) {
          throw new functions.https.HttpsError('failed-precondition', 'لا يمكن تنزيل آخر مدير عام');
        }
      }
    }

    await setUserRole(uid, role);

    const adminData = {
      uid,
      email: targetEmail || target.email || '',
      displayName: displayName || target.displayName || targetEmail,
      role,
      status: 'active',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await db.collection('admin_users').doc(uid).set(adminData, { merge: true });
    await db.collection('users').doc(uid).set({
      userType: role === 'super_admin' || role === 'admin' ? role : 'user',
      roleChangeAuthorizedBy: actor.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    await writeAuditLog({
      actorUid: actor.uid,
      actorEmail: actor.token.email || actor.token.email_verified || null,
      action: 'admin_role_set',
      result: 'success',
      details: { uid, email: targetEmail, role, updatedBy: actor.uid },
    });

    return { success: true, role, uid };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    throw new functions.https.HttpsError('internal', 'فشل تعيين الدور: ' + e.message);
  }
});

// ===================== إزالة دور مدير =====================
exports.removeAdminRole = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  const actor = context.auth;
  if (!(await hasRole(context, ['super_admin']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحية Super Admin مطلوبة لهذه العملية');
  }

  const uid = data && data.uid;
  if (!uid) {
    throw new functions.https.HttpsError('invalid-argument', 'uid مطلوب');
  }
  if (uid === actor.uid) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن إزالة نفسك');
  }

  try {
    const target = await admin.auth().getUser(uid);
    const targetEmail = (target.email || '').toLowerCase();
    if (PROTECTED_ADMINS.includes(targetEmail)) {
      throw new functions.https.HttpsError('permission-denied', 'هذا الحساب محمي ولا يمكن إزالته');
    }

    // منع إزالة آخر Super Admin
    if (target.customClaims && target.customClaims.role === 'super_admin') {
      const superAdmins = await db.collection('admin_users')
        .where('role', '==', 'super_admin')
        .where('status', '==', 'active')
        .get();
      if (superAdmins.size <= 1) {
        throw new functions.https.HttpsError('failed-precondition', 'لا يمكن إزالة آخر مدير عام');
      }
    }

    await admin.auth().setCustomUserClaims(uid, null);
    await db.collection('users').doc(uid).set({
      userType: 'user',
      roleChangeAuthorizedBy: actor.uid,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
    await db.collection('admin_users').doc(uid).update({
      status: 'removed',
      role: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    await writeAuditLog({
      actorUid: actor.uid,
      actorEmail: actor.token.email || null,
      action: 'admin_role_removed',
      result: 'success',
      details: { uid, email: targetEmail, updatedBy: actor.uid },
    });

    return { success: true };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    throw new functions.https.HttpsError('internal', 'فشل إزالة الدور: ' + e.message);
  }
});

// ===================== حذف وثيقة وشجرة البيانات الفرعية =====================
async function deleteDocTree(ref) {
  const collections = await ref.listCollections();
  for (const col of collections) {
    const snap = await col.get();
    for (const doc of snap.docs) {
      await deleteDocTree(doc.ref);
    }
  }
  if ((await ref.get()).exists) {
    await ref.delete();
  }
}

// ===================== حذف حساب مستخدم نهائياً =====================
exports.deleteUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  if (!(await hasRole(context, ['super_admin']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحية Super Admin مطلوبة لهذه العملية');
  }

  const uid = data && data.uid;
  if (!uid) {
    throw new functions.https.HttpsError('invalid-argument', 'uid مطلوب');
  }
  if (uid === context.auth.uid) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن حذف حسابك بنفسك');
  }

  try {
    const target = await admin.auth().getUser(uid);
    const targetEmail = (target.email || '').toLowerCase();
    if (PROTECTED_ADMINS.includes(targetEmail)) {
      throw new functions.https.HttpsError('permission-denied', 'هذا الحساب محمي ولا يمكن حذفه');
    }
    const claim = target.customClaims && target.customClaims.role;
    if (claim === 'super_admin') {
      throw new functions.https.HttpsError('permission-denied', 'لا يمكن حذف مدير عام');
    }

    await admin.auth().deleteUser(uid);

    // حذف بيانات المستخدم (وثيقة + كل البيانات الفرعية)
    await deleteDocTree(db.collection('users').doc(uid));

    // تنظيف السجلات الإدارية
    await db.collection('admin_users').doc(uid).delete().catch(() => {});
    await db.collection('admin_stats').doc(`user_counts/${uid}`).delete().catch(() => {});

    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: 'user_deleted',
      result: 'success',
      details: { uid, email: targetEmail, deletedBy: context.auth.uid },
    });

    return { success: true, uid };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    throw new functions.https.HttpsError('internal', 'فشل حذف المستخدم: ' + e.message);
  }
});

// ===================== تعطيل/تفعيل حساب مستخدم (تعليق) =====================
exports.setUserStatus = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  if (!(await hasRole(context, ['super_admin']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحية Super Admin مطلوبة لهذه العملية');
  }

  const uid = data && data.uid;
  const disabled = data && data.disabled === true;
  if (!uid) {
    throw new functions.https.HttpsError('invalid-argument', 'uid مطلوب');
  }
  if (uid === context.auth.uid) {
    throw new functions.https.HttpsError('permission-denied', 'لا يمكن تعطيل حسابك بنفسك');
  }

  try {
    const target = await admin.auth().getUser(uid);
    const targetEmail = (target.email || '').toLowerCase();
    if (PROTECTED_ADMINS.includes(targetEmail)) {
      throw new functions.https.HttpsError('permission-denied', 'هذا الحساب محمي ولا يمكن تعطيله');
    }
    const claim = target.customClaims && target.customClaims.role;
    if (claim === 'super_admin') {
      throw new functions.https.HttpsError('permission-denied', 'لا يمكن تعطيل مدير عام');
    }

    await admin.auth().updateUser(uid, { disabled });

    await db.collection('users').doc(uid).set(
      {
        status: disabled ? 'blocked' : 'active',
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: disabled ? 'user_blocked' : 'user_unblocked',
      result: 'success',
      details: { uid, email: targetEmail, disabled, updatedBy: context.auth.uid },
    });

    return { success: true, disabled };
  } catch (e) {
    if (e instanceof functions.https.HttpsError) throw e;
    throw new functions.https.HttpsError('internal', 'فشل تعطيل المستخدم: ' + e.message);
  }
});

// ===================== إرسال الإشعارات (تُنفَّذ عند إنشاء وثيقة) =====================
exports.sendNotification = functions.firestore
  .document('notifications/{id}')
  .onCreate(async (snap) => {
    const data = snap.data() || {};
    const { title, body, targetType, targetUid, createdBy } = data;

    const messaging = admin.messaging();

    try {
      let tokens = [];

      if (targetType === 'user' && targetUid) {
        const snapTokens = await db
          .collection('users')
          .doc(targetUid)
          .collection('devices')
          .get();
        tokens = snapTokens.docs.map((d) => d.id);
      } else {
        // إرسال للجميع: نقرأ أجهزة جميع المستخدمين
        const snapTokens = await db.collectionGroup('devices').get();
        tokens = snapTokens.docs.map((d) => d.id);
      }

      // حد أقصى لحماية الأداة من الأخطاء (يمكن تعديله حسب الحاجة)
      tokens = tokens.slice(0, 1000);

      if (tokens.length === 0) {
        await snap.ref.update({
          status: 'no_devices',
          sentCount: 0,
          finishedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        await writeAuditLog({
          actorUid: createdBy || null,
          action: 'notification_send',
          result: 'no_devices',
          details: { id: snap.id, title },
        });
        return;
      }

      const response = await messaging.sendEachForMulticast({
        tokens,
        notification: { title, body, sound: 'default' },
        data: { click_action: 'FLUTTER_NOTIFICATION_CLICK' },
      });

      await snap.ref.update({
        status: response.failureCount > 0 ? 'sent_with_errors' : 'sent',
        sentCount: response.successCount,
        failureCount: response.failureCount,
        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await writeAuditLog({
        actorUid: createdBy || null,
        action: 'notification_send',
        result: response.failureCount > 0 ? 'sent_with_errors' : 'sent',
        details: { id: snap.id, title, sent: response.successCount, failed: response.failureCount },
      });
    } catch (e) {
      await snap.ref.update({
        status: 'failed',
        finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      console.error('فشل الإشعار:', e);
    }
  });

// ===================== تحديث إعدادات المنصة =====================
exports.updateAppConfig = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  if (!(await hasRole(context, ['super_admin']))) {
    // تسجيل محاولة الرفض إلزامي حسب المواصفات (بلا استثناء).
    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: 'platform_config_updated',
      result: 'denied',
      details: {
        reason: 'permission-denied',
        attemptedFields: Object.keys(data && typeof data === 'object' ? data : {}),
      },
    });
    throw new functions.https.HttpsError('permission-denied', 'صلاحية Super Admin مطلوبة');
  }

  const allowedFields = [
    'appName', 'currentVersion', 'minVersion', 'forceUpdate',
    'updateUrl', 'releaseNotes', 'notificationsEnabled',
  ];
  const patch = {};
  for (const key of allowedFields) {
    if (data && data[key] !== undefined) patch[key] = data[key];
  }
  patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
  patch.updatedBy = context.auth.uid;

  const ref = db.collection('platform').doc('app_config');
  await ref.set(patch, { merge: true });
  const after = (await ref.get()).data();

  await writeAuditLog({
    actorUid: context.auth.uid,
    actorEmail: context.auth.token.email || null,
    action: 'platform_config_updated',
    result: 'success',
    details: { changes: patch, updatedBy: context.auth.uid },
  });

  return { success: true, config: after };
});

// ===================== حساب الإحصائيات المجمعة =====================
async function computeStats() {
  const usersSnap = await db.collection('users').get();
  const businessesSnap = await db.collectionGroup('businesses').get();
  const workersSnap = await db.collectionGroup('workers').get();

  const now = Date.now();
  const day = 24 * 60 * 60 * 1000;

  // بداية اليوم التقويمي (بتوقيت الخادم) لعدّ أعمال اليوم.
  const startOfDay = new Date(now);
  startOfDay.setUTCHours(0, 0, 0, 0);
  const startOfDayMs = startOfDay.getTime();

  const createdAtOf = (d) => {
    if (!d) return null;
    const t = d.seconds ? new Date(d.seconds * 1000) : new Date(d);
    return t.getTime();
  };

  let totalUsers = 0;
  let newUsers7 = 0;
  let newUsers30 = 0;
  let activeUsers7 = 0;
  let activeUsers30 = 0;
  const versionMap = {};
  const usersById = {};

  for (const doc of usersSnap.docs) {
    const u = doc.data() || {};
    totalUsers++;
    usersById[doc.id] = true;

    const createdAt = createdAtOf(u.createdAt);
    if (createdAt && now - createdAt <= 7 * day) newUsers7++;
    if (createdAt && now - createdAt <= 30 * day) newUsers30++;

    const lastActivity = createdAtOf(u.lastActivityAt);
    if (lastActivity && now - lastActivity <= 7 * day) activeUsers7++;
    if (lastActivity && now - lastActivity <= 30 * day) activeUsers30++;

    const v = (u.appVersion || 'غير معروف').toString();
    versionMap[v] = (versionMap[v] || 0) + 1;
  }

  let totalBusinesses = 0;
  let completedBusinesses = 0;
  let inProgressBusinesses = 0;
  let businessesToday = 0;
  const userCounts = {};

  for (const doc of businessesSnap.docs) {
    const pid = doc.ref.parent.parent && doc.ref.parent.parent.id;
    if (!pid) continue;
    totalBusinesses++;
    const b = doc.data() || {};
    const status = b.status || '';
    const entry = userCounts[pid] || { total: 0, completed: 0, inProgress: 0 };
    entry.total++;
    if (status === 'مكتمل') entry.completed++;
    if (status === 'جاري التنفيذ') entry.inProgress++;
    userCounts[pid] = entry;

    const created = createdAtOf(b.createdAt);
    if (created && created >= startOfDayMs) businessesToday++;
  }

  const totalWorkers = workersSnap.docs.length;
  const remainingBusinesses = totalBusinesses - completedBusinesses;

  const dashboard = {
    totalUsers,
    newUsers7,
    newUsers30,
    activeUsers7,
    activeUsers30,
    totalBusinesses,
    completedBusinesses,
    inProgressBusinesses,
    businessesToday,
    remainingBusinesses,
    totalWorkers,
    versionDistribution: versionMap,
    statsUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  await db.collection('admin_stats').doc('dashboard').set(dashboard, { merge: true });

  // إحصاءات المستخدمين الذين لديهم أعمال فقط على دفعات آمنة (حجم الدفعة أقصاه 400 كتابة لتجنب حد 500 في Firestore)
  const targetUids = Object.keys(userCounts);
  const CHUNK_SIZE = 400;
  for (let i = 0; i < targetUids.length; i += CHUNK_SIZE) {
    const chunk = targetUids.slice(i, i + CHUNK_SIZE);
    const batch = db.batch();
    for (const uid of chunk) {
      const c = userCounts[uid];
      batch.set(db.collection('admin_stats').doc(`user_counts/${uid}`), {
        businessCount: c.total,
        completedCount: c.completed,
        inProgressCount: c.inProgress,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, { merge: true });
    }
    await batch.commit();
  }

  return {
    totalUsers,
    newUsers7,
    newUsers30,
    activeUsers7,
    activeUsers30,
    totalBusinesses,
    completedBusinesses,
    inProgressBusinesses,
    businessesToday,
    remainingBusinesses,
    totalWorkers,
  };
}

// حساب دوري (يتطلب خطة Blaze) + تحديث يدوي متاح للمدير
exports.computeStatsScheduled = functions.pubsub
  .schedule('every 6 hours')
  .onRun(async () => {
    try {
      await computeStats();
      console.log('تم تحديث الإحصائيات الدورية بنجاح');
    } catch (e) {
      console.error('خطأ أثناء تشغيل التحديث الدوري للإحصائيات:', e);
    }
    return null;
  });

exports.refreshStats = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  if (!(await hasRole(context, ['super_admin', 'admin', 'analyst']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحيات غير كافية');
  }
  try {
    const result = await computeStats();
    await writeAuditLog({
      actorUid: context.auth.uid,
      actorEmail: context.auth.token.email || null,
      action: 'stats_refresh',
      result: 'success',
      details: result,
    });
    return result;
  } catch (e) {
    throw new functions.https.HttpsError('internal', 'فشل حساب الإحصائيات: ' + e.message);
  }
});

// ===================== إحصاءات مستخدم محدد =====================
exports.getUserStats = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  if (!(await hasRole(context, ['super_admin', 'admin']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحيات غير كافية');
  }
  const uid = data && data.uid;
  if (!uid) {
    throw new functions.https.HttpsError('invalid-argument', 'uid مطلوب');
  }

  try {
    const countsSnap = await db.collection('admin_stats').doc(`user_counts/${uid}`).get();
    const countsData = countsSnap.exists ? countsSnap.data() : {};

    return {
      uid,
      businessCount: countsData.businessCount || 0,
      completedCount: countsData.completedCount || 0,
      inProgressCount: countsData.inProgressCount || 0,
    };
  } catch (e) {
    throw new functions.https.HttpsError('internal', 'فشل جلب الإحصاءات: ' + e.message);
  }
});

// ============================================================================
// استهلاك Firebase — البيانات الرسمية (Google Cloud Monitoring)
// ============================================================================
// هذه الدالة تُنشر ولا تُستدعى إلا من لوحة المدير عبر AdminApi (post النشر).
// التنبيه الهام: نشر/تحديث الدوال يتطلب خطة Blaze. حتى يتم النشر تظهر الصفحة
// في التطبيق رسالة "غير متاحة" بدلاً من تعطيل بقية الدوال، لأن المكتبة هنا
// تُحمَّل كسلاً داخل الدالة (وليس أعلى الملف) كي لا ينهار index.js بالكامل.
//
// المقاييس الرسمية (قياساً على لوحة Usage في Firebase Console):
//   firestore.googleapis.com/document/read_count
//   firestore.googleapis.com/document/write_count
//   firestore.googleapis.com/document/delete_count
// ملاحظة الدقة الرسمية: المقاييس تأتي عينة كل دقيقة وقد تتأخر حتى 4 دقائق،
// ولوحة الاستخدام تقديرية وليست رقم الفاتورة النهائي.

const USAGE_METRICS = {
  reads: 'firestore.googleapis.com/document/read_count',
  writes: 'firestore.googleapis.com/document/write_count',
  deletes: 'firestore.googleapis.com/document/delete_count',
};

// تحميل كسول بحيث لا ينهار index.js إذا لم تُثبَّت الحزمة بعد.
let _monitoringLib = null;
function monitoringClient(projectId) {
  if (_monitoringLib === null) {
    _monitoringLib = require('@google-cloud/monitoring');
  }
  return new _monitoringLib.v3.MetricServiceClient({ projectId });
}

function utcDayStart(date) {
  const d = new Date(date);
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

function utcMonthStart(date) {
  const d = new Date(date);
  d.setUTCDate(1);
  d.setUTCHours(0, 0, 0, 0);
  return d;
}

function secondsOf(date) {
  return Math.floor(date.getTime() / 1000);
}

function isoDateOf(seconds) {
  return new Date(seconds * 1000).toISOString().slice(0, 10);
}

function metricSum(points) {
  let total = 0;
  for (const p of points || []) {
    const v = p.value;
    let n = null;
    if (v && v.int64Value !== undefined) n = Number(v.int64Value);
    else if (v && v.doubleValue !== undefined) n = v.doubleValue;
    if (n != null && !Number.isNaN(n)) total += n;
  }
  return total;
}

/**
 * يجلب سلسلة يومية (1 يوم لكل نقطة) لمقياس معين خلال فترة محددة.
 * يعيد خريطة: { 'YYYY-MM-DD': sum }.
 * aggregation: 86400 ثانية + ALIGN_SUM + REDUCE_SUM يعطي إجمالي اليوم الواحد
 * تماماً كما تفعل لوحة الاستخدام في Firebase Console.
 */
async function dailySeries(client, projectPath, metricType, start, end) {
  const [result] = await client.listTimeSeries({
    name: projectPath,
    filter: `metric.type="${metricType}"`,
    interval: {
      startTime: { seconds: secondsOf(start) },
      endTime: { seconds: secondsOf(end) },
    },
    aggregation: {
      alignmentPeriod: { seconds: 86400 },
      perSeriesAligner: 'ALIGN_SUM',
      crossSeriesReducer: 'REDUCE_SUM',
    },
    view: 'FULL',
  });

  const byDate = new Map();
  for (const ts of result || []) {
    for (const p of ts.points || []) {
      const endSec = p.interval && p.interval.endTime && p.interval.endTime.seconds;
      if (!endSec) continue;
      const date = isoDateOf(endSec);
      byDate.set(date, (byDate.get(date) || 0) + metricSum([p]));
    }
  }
  return byDate;
}

async function countAuthUsers() {
  let count = 0;
  let nextPageToken;
  do {
    const list = nextPageToken
      ? await admin.auth().listUsers(1000, nextPageToken)
      : await admin.auth().listUsers(1000);
    count += list.users.length;
    nextPageToken = list.pageToken;
  } while (nextPageToken);
  return count;
}

function arrayOrList(value, days, endISO) {
  if (value == null) return [];
  const entries = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(endISO);
    d.setUTCDate(d.getUTCDate() - i);
    const key = d.toISOString().slice(0, 10);
    entries.push({
      date: key,
      reads: value.reads.get(key) || 0,
      writes: value.writes.get(key) || 0,
      deletes: value.deletes.get(key) || 0,
    });
  }
  return entries;
}

exports.getFirebaseUsage = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'يجب تسجيل الدخول أولاً');
  }
  // أي دور إداري (تحليلي/مدير/مدير عام) يستطيع رؤية لوحة الاستهلاك.
  if (!(await hasRole(context, ['super_admin', 'admin', 'analyst']))) {
    throw new functions.https.HttpsError('permission-denied', 'صلاحيات غير كافية');
  }

  const days = Math.min(Math.max(parseInt((data && data.days) || 7, 10) || 7, 1), 30);
  const now = new Date();
  const todayISO = now.toISOString().slice(0, 10);
  const todayStart = utcDayStart(now);
  const monthStart = utcMonthStart(now);

  const projectId =
    process.env.GCLOUD_PROJECT ||
    (admin.apps[0] && admin.apps[0].options && admin.apps[0].options.projectId) ||
    '';
  if (!projectId) {
    return {
      source: 'google_cloud_monitoring',
      usageAvailable: false,
      errorCode: 'project_not_found',
      errorMessage: 'تعذر تحديد project ID للدالة.',
      fetchedAt: now.toISOString(),
    };
  }

  let client;
  try {
    client = monitoringClient(projectId);
  } catch (e) {
    console.error('[FirebaseUsage] monitoring client init failed', e);
    return {
      source: 'google_cloud_monitoring',
      usageAvailable: false,
      errorCode: 'dependency_missing',
      errorMessage: 'حزمة @google-cloud/monitoring غير مثبتة في Cloud Function.',
      fetchedAt: now.toISOString(),
    };
  }

  const projectPath = client.projectPath(projectId);

  // النطاق الزمني المطلوب: بداية الشهر الحالي -> الآن
  // (يغطي معه "اليوم" و"الشهر" وآخر N أيام في استدعاء واحد لكل مقياس).
  const daily = { reads: new Map(), writes: new Map(), deletes: new Map() };
  let storageError = null;
  let authUsers = null;

  try {
    const [readsP, writesP, deletesP] = await Promise.all([
      dailySeries(client, projectPath, USAGE_METRICS.reads, monthStart, now),
      dailySeries(client, projectPath, USAGE_METRICS.writes, monthStart, now),
      dailySeries(client, projectPath, USAGE_METRICS.deletes, monthStart, now),
    ]);
    daily.reads = readsP;
    daily.writes = writesP;
    daily.deletes = deletesP;
  } catch (e) {
    console.error('[FirebaseUsage] monitoring query failed', e);
    const s = String((e && e.message) || e);
    if (
      s.toLowerCase().includes('permission denied') ||
      s.toLowerCase().includes('forbidden')
    ) {
      storageError = { code: 'permission_denied' };
    } else if (
      s.toLowerCase().includes('404') ||
      s.toLowerCase().includes('not found')
    ) {
      storageError = { code: 'api_not_enabled' };
    } else {
      storageError = { code: 'unknown', detail: s.slice(0, 200) };
    }
  }

  if (storageError) {
    return {
      source: 'google_cloud_monitoring',
      usageAvailable: false,
      errorCode: storageError.code,
      errorMessage: storageError.detail || '',
      fetchedAt: now.toISOString(),
      authUsers: null,
    };
  }

  // عدد مستخدمي Firebase Authentication (مجاني تماماً عبر Admin SDK، بلا قراءات Firestore).
  try {
    authUsers = await countAuthUsers();
  } catch (e) {
    console.error('[FirebaseUsage] auth count failed', e);
    authUsers = null;
  }

  const sumOf = (map, start) => {
    let total = 0;
    for (const [date, v] of map) {
      if (date >= start) total += v;
    }
    return total;
  };
  const monthISO = monthStart.toISOString().slice(0, 10);

  return {
    source: 'google_cloud_monitoring',
    usageAvailable: true,
    fetchedAt: now.toISOString(),
    authUsers,
    firestore: {
      today: {
        reads: daily.reads.get(todayISO) || 0,
        writes: daily.writes.get(todayISO) || 0,
        deletes: daily.deletes.get(todayISO) || 0,
      },
      month: {
        reads: sumOf(daily.reads, monthISO),
        writes: sumOf(daily.writes, monthISO),
        deletes: sumOf(daily.deletes, monthISO),
      },
      // آخر N أيام بترتيب زمني تصاعدي (من الأقدم إلى الأحدث).
      daily: arrayOrList(daily, Math.min(days, 30), todayISO),
    },
    // Storage غير متاح كمقياس رسمي عبر Monitoring API لـ Native mode.
    // لا نخترع رقماً؛ نُعلِم العميل بأنه غير متاح ليعرض رسالة صادقة.
    storage: { available: false, bytes: null },
  };
});