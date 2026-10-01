// Regression test: suspending an OWNER must lock out that owner's delegates.
//
// Fixture: Muhammad (owner) delegates to Ali (all permissions) and
// Qasim (workers only).
// Expect: once Muhammad is suspended, Ali and Qasim lose every path into
// his data - owner profile, their own membership docs, businesses,
// workers, expenses and the collectionGroup membership lookup - while
// still reading their OWN profiles. Lifting the suspension restores
// access (guards against over-blocking).
//
// This covers the reported bug: every check only looked at the delegate's
// own users/{uid}, so they entered a suspended owner's workspace, and the
// rules leaked that data because the gate never tested the owner status.

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const fs = require("fs");
const assert = require("node:assert/strict");

const OWNER = "muhammad";
const ALI = "ali";
const QASIM = "qasim";

let testEnv;

const fullPermissions = {
  businesses: { read: true, create: true, update: true, delete: true },
  workers: { read: true, create: true, update: true, delete: true },
  expenses: { read: true, create: true, update: true, delete: true },
};

const workersOnlyPermissions = {
  businesses: { read: false, create: false, update: false, delete: false },
  workers: { read: true, create: true, update: true, delete: true },
  expenses: { read: false, create: false, update: false, delete: false },
};

async function suspendOwner() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection("users")
      .doc(OWNER)
      .update({ status: "suspended", isActive: false });
  });
}

async function unsuspendOwner() {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .collection("users")
      .doc(OWNER)
      .update({ status: "active", isActive: true });
  });
}

// Reads a user doc with rules off. withSecurityRulesDisabled does NOT forward
// the callback's return value, so the snapshot has to be captured from outside.
async function readUser(uid) {
  let data = null;
  await testEnv.withSecurityRulesDisabled(async (context) => {
    const snap = await context.firestore().collection("users").doc(uid).get();
    data = snap.data();
  });
  return data;
}

const asAli = () =>
  testEnv.authenticatedContext(ALI).firestore();
const asQasim = () =>
  testEnv.authenticatedContext(QASIM).firestore();
const ownerRef = (db, sub) => db.collection("users").doc(OWNER).collection(sub);

describe("إيقاف المالك يمنع تابعيه من الوصول", function () {
  this.timeout(15000);

  before(async function () {
    testEnv = await initializeTestEnvironment({
      projectId: "tasheel-e4d47",
      firestore: {
        host: "127.0.0.1",
        port: 8080,
        rules: fs.readFileSync("../firestore.rules", "utf8"),
      },
    });

    await testEnv.withSecurityRulesDisabled(async (context) => {
      const db = context.firestore();

      for (const [uid, name] of [
        [OWNER, "محمد"],
        [ALI, "علي"],
        [QASIM, "قاسم"],
      ]) {
        await db.collection("users").doc(uid).set({
          uid,
          name,
          userType: "user",
          status: "active",
          isActive: true,
        });
      }

      // تفويض علي: كل الصلاحيات بلا scope (تفويض كامل).
      await db
        .collection("users")
        .doc(OWNER)
        .collection("team_members")
        .doc(ALI)
        .set({
          uid: ALI,
          ownerUid: OWNER,
          name: "علي",
          status: "active",
          role: "admin",
          permissions: fullPermissions,
        });

      // تفويض قاسم: العمال فقط.
      await db
        .collection("users")
        .doc(OWNER)
        .collection("team_members")
        .doc(QASIM)
        .set({
          uid: QASIM,
          ownerUid: OWNER,
          name: "قاسم",
          status: "active",
          role: "member",
          permissions: workersOnlyPermissions,
        });

      await db
        .collection("users")
        .doc(OWNER)
        .collection("businesses")
        .doc("biz1")
        .set({ name: "محل محمد", ownerUid: OWNER });
      await db
        .collection("users")
        .doc(OWNER)
        .collection("workers")
        .doc("wk1")
        .set({ name: "سالم", ownerUid: OWNER });
      await db
        .collection("users")
        .doc(OWNER)
        .collection("expenses")
        .doc("ex1")
        .set({ title: "إيجار", ownerUid: OWNER });

      // ⭐ بيانات قاسم الشخصية (ليست من محمد). السيناريو المطلوب: قاسم
      //account own is active، فيجب أن يبقى يرى وتعدّل حساباته هو حتى
      //بعد إيقاف محمد. أي حظر هنا = خطأ (وهو ما كان يحدث في التطبيق).
      await db
        .collection("users")
        .doc(QASIM)
        .collection("businesses")
        .doc("qbiz1")
        .set({ name: "محل قاسم", ownerUid: QASIM });
      await db
        .collection("users")
        .doc(QASIM)
        .collection("workers")
        .doc("qwk1")
        .set({ name: "عامل قاسم", ownerUid: QASIM });
      await db
        .collection("users")
        .doc(QASIM)
        .collection("expenses")
        .doc("qex1")
        .set({ title: "مصاريف قاسم", ownerUid: QASIM });
    });
  });

  after(async function () {
    await unsuspendOwner();
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  // ============ خط الأساس: المالك نشط ⇒ كل شيء يعمل كما يجب ============

  describe("حين يكون المالك نشطاً", function () {
    it("علي يقرأ بروفايل مالكه محمد", async function () {
      await assertSucceeds(
        asAli().collection("users").doc(OWNER).get()
      );
    });

    it("علي يقرأ وثيقة عضويته", async function () {
      await assertSucceeds(
        ownerRef(asAli(), "team_members").doc(ALI).get()
      );
    });

    it("علي يسرد الأعمال ويقرأها", async function () {
      await assertSucceeds(
        ownerRef(asAli(), "businesses").get()
      );
    });

    it("علي ينشئ عملاً جديداً", async function () {
      await assertSucceeds(
        ownerRef(asAli(), "businesses").doc("biz-from-ali").set({
          name: "محل جديد",
          ownerUid: OWNER,
        })
      );
    });

    it("قاسم يسرد العمال", async function () {
      await assertSucceeds(
        ownerRef(asQasim(), "workers").get()
      );
    });

    it("قاسم لا يسرد الأعمال (لا يملك الصلاحية)", async function () {
      await assertFails(
        ownerRef(asQasim(), "businesses").get()
      );
    });

    it("قاسم يجد عضويته عبر collectionGroup", async function () {
      await assertSucceeds(
        asQasim()
          .collectionGroup("team_members")
          .where("uid", "==", QASIM)
          .get()
      );
    });
  });

  // ============ السيناريو المُبلَّغ: إيقاف المالك ============

  describe("بعد إيقاف حساب محمد من لوحة الإدارة", function () {
    before(suspendOwner);

    // The two metadata paths below are deliberately NOT owner-gated: adding
    // accountStatusOf() to them creates a get() recursion deadlock that locks
    // the delegate out even of an ACTIVE owner (verified in the emulator).
    // They expose only profile/membership metadata, never business data, and
    // the login block is enforced client-side by AccountAccessGuard.
    it("Ali can still read the owner profile doc (metadata only)", async function () {
      await assertSucceeds(
        asAli().collection("users").doc(OWNER).get()
      );
    });

    it("Ali can still read his own membership doc (metadata only)", async function () {
      await assertSucceeds(
        ownerRef(asAli(), "team_members").doc(ALI).get()
      );
    });

    it("Qasim can still read his own membership doc (metadata only)", async function () {
      await assertSucceeds(
        ownerRef(asQasim(), "team_members").doc(QASIM).get()
      );
    });

    it("علي لا يسرد أعمال مالكه", async function () {
      await assertFails(
        ownerRef(asAli(), "businesses").get()
      );
    });

    it("علي لا يقرأ عملاً محدداً لمالكه", async function () {
      await assertFails(
        ownerRef(asAli(), "businesses").doc("biz1").get()
      );
    });

    it("علي لا ينشئ عملاً في حساب مالكه", async function () {
      await assertFails(
        ownerRef(asAli(), "businesses").doc("biz-attempt").set({
          name: "محاولة",
          ownerUid: OWNER,
        })
      );
    });

    it("علي لا يعدّل عملاً في حساب مالكه", async function () {
      await assertFails(
        ownerRef(asAli(), "businesses").doc("biz1").update({
          name: "معدّل",
        })
      );
    });

    it("علي لا يحذف عملاً في حساب مالكه", async function () {
      await assertFails(
        ownerRef(asAli(), "businesses").doc("biz1").delete()
      );
    });

    it("قاسم لا يسرد عمال مالكه", async function () {
      await assertFails(
        ownerRef(asQasim(), "workers").get()
      );
    });

    it("قاسم لا يقرأ عاملاً محدداً لمالكه", async function () {
      await assertFails(
        ownerRef(asQasim(), "workers").doc("wk1").get()
      );
    });

    it("قاسم لا يقرأ مصروفات مالكه", async function () {
      await assertFails(
        ownerRef(asQasim(), "expenses").doc("ex1").get()
      );
    });

    it("Qasim still finds his membership via collectionGroup (guard handles the block)", async function () {
      await assertSucceeds(
        asQasim()
          .collectionGroup("team_members")
          .where("uid", "==", QASIM)
          .get()
      );
    });

    it("Ali can still set mustChangePassword=false on his own membership", async function () {
      await assertSucceeds(
        ownerRef(asAli(), "team_members").doc(ALI).update({
          mustChangePassword: false,
        })
      );
    });
  });

  // ============ بيان قاسم الشخصي يبقى متاحاً رغم إيقاف محمد ============
  // هذا هو جوهر السيناريو: "أنت استطيع الدخول لحسابي فقط". القواعد يجب أن
  // تمنع قاسم من بيانات محمد (أعلاه) دون أن تمسّ بياناته الشخصية إطلاقاً،
  // لأن users/{QASIM} ما زال نشطاً ومستقلاً عن حساب محمد.

  describe("بيانات قاسم الشخصية أثناء إيقاف محمد", function () {
    before(suspendOwner);

    it("Qasim lists his OWN businesses", async function () {
      await assertSucceeds(
        asQasim().collection("users").doc(QASIM).collection("businesses").get()
      );
    });

    it("Qasim reads his OWN worker", async function () {
      await assertSucceeds(
        asQasim()
          .collection("users")
          .doc(QASIM)
          .collection("workers")
          .doc("qwk1")
          .get()
      );
    });

    it("Qasim writes to his OWN business", async function () {
      await assertSucceeds(
        asQasim()
          .collection("users")
          .doc(QASIM)
          .collection("businesses")
          .doc("qbiz1")
          .update({ name: "محل قاسم المعدّل" })
      );
    });

    it("Qasim writes to his OWN expense", async function () {
      await assertSucceeds(
        asQasim()
          .collection("users")
          .doc(QASIM)
          .collection("expenses")
          .doc("qex1")
          .update({ title: "مصاريف معدّلة" })
      );
    });

    it("Qasim still cannot touch Muhammad's business (no over-reach)", async function () {
      await assertFails(
        ownerRef(asQasim(), "businesses").doc("biz1").update({ name: "مُخترق" })
      );
    });
  });

  // ============ لا إفراط: رفع الإيقاف يعيد الصلاحيات ============

  describe("بعد إعادة تفعيل حساب محمد", function () {
    before(unsuspendOwner);

    it("Ali can still read his own profile (his account is active)", async function () {
      await assertSucceeds(
        asAli().collection("users").doc(ALI).get()
      );
    });

    it("Qasim can still read his own profile (his account is active)", async function () {
      await assertSucceeds(
        asQasim().collection("users").doc(QASIM).get()
      );
    });

    it("Ali lists businesses again", async function () {
      await assertSucceeds(
        ownerRef(asAli(), "businesses").get()
      );
    });

    it("Qasim lists workers again", async function () {
      await assertSucceeds(
        ownerRef(asQasim(), "workers").get()
      );
    });

    it("Qasim finds his membership via collectionGroup again", async function () {
      await assertSucceeds(
        asQasim()
          .collectionGroup("team_members")
          .where("uid", "==", QASIM)
          .get()
      );
    });

    it("Ali can read the owner profile again", async function () {
      await assertSucceeds(
        asAli().collection("users").doc(OWNER).get()
      );
    });
  });

  // ============ Admin manual suspend/activate ============
  // This is the path the whole scenario rests on: if the rules reject the
  // {status, isActive} write from the panel, no suspension can ever exist.

  describe("Admin manual suspend/activate", function () {
    it("Admin can suspend a user (status + isActive)", async function () {
      const db = testEnv.authenticatedContext("adminUser", { role: "admin" }).firestore();
      await assertSucceeds(
        db.collection("users").doc(ALI).update({
          status: "suspended",
          isActive: false,
          updatedAt: new Date(),
        })
      );
    });

    it("Admin can re-activate a user", async function () {
      const db = testEnv.authenticatedContext("adminUser", { role: "admin" }).firestore();
      await assertSucceeds(
        db.collection("users").doc(ALI).update({
          status: "active",
          isActive: true,
        })
      );
    });

    it("A user cannot self-suspend via status+isActive", async function () {
      await assertFails(
        asAli()
          .collection("users")
          .doc(ALI)
          .update({ status: "suspended", isActive: false, updatedAt: new Date() })
      );
    });

    it("A user cannot set his own isActive=false", async function () {
      await assertFails(
        asAli().collection("users").doc(ALI).update({ isActive: false })
      );
    });

    it("A suspended user cannot re-activate himself", async function () {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc(QASIM).update({
          status: "suspended",
          isActive: false,
        });
      });

      await assertFails(
        asQasim().collection("users").doc(QASIM).update({
          status: "active",
          isActive: true,
        })
      );

      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().collection("users").doc(QASIM).update({
          status: "active",
          isActive: true,
        });
      });
    });
  });

  // ============ Panel write path (set + merge, not update) ============
  // admin_firestore_service.setUserBlockedStatus uses
  //   .set({status, isActive, updatedAt}, {merge: true})
  // which is a WRITE, not an UPDATE. Firestore evaluates those through
  // different branches, so the panel path needs its own coverage.
  // `updatedAt` is written as a real Date rather than FieldValue
  // .serverTimestamp() because the sentinel comes from a different
  // @firebase/firestore copy than the one rules-unit-testing serializes
  // with. Rules gate on affected KEYS, and the key set is identical.

  describe("Admin panel write path (set with merge)", function () {
    it("Admin can suspend via set+merge (exact panel call)", async function () {
      const db = testEnv
        .authenticatedContext("adminUser", { role: "admin" })
        .firestore();
      await assertSucceeds(
        db.collection("users").doc(ALI).set(
          { status: "suspended", isActive: false, updatedAt: new Date() },
          { merge: true }
        )
      );
      const after = await readUser(ALI);
      assert.equal(after.status, "suspended");
      assert.equal(after.isActive, false);
    });

    it("Admin can re-activate via set+merge", async function () {
      const db = testEnv
        .authenticatedContext("adminUser", { role: "admin" })
        .firestore();
      await assertSucceeds(
        db.collection("users").doc(ALI).set(
          { status: "active", isActive: true, updatedAt: new Date() },
          { merge: true }
        )
      );
      const after = await readUser(ALI);
      assert.equal(after.status, "active");
      assert.equal(after.isActive, true);
    });

    it("super_admin recognised by userType doc can suspend via set+merge", async function () {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context
          .firestore()
          .collection("users")
          .doc("bossDoc")
          .set({
            uid: "bossDoc",
            userType: "super_admin",
            status: "active",
            isActive: true,
          });
      });
      const db = testEnv.authenticatedContext("bossDoc").firestore();
      await assertSucceeds(
        db.collection("users").doc(QASIM).set(
          { status: "suspended", isActive: false, updatedAt: new Date() },
          { merge: true }
        )
      );
    });

    it("A user cannot self-suspend via set+merge", async function () {
      await assertFails(
        asAli()
          .collection("users")
          .doc(ALI)
          .set(
            { status: "suspended", isActive: false, updatedAt: new Date() },
            { merge: true }
          )
      );
    });

    it("A user cannot escalate to admin via set+merge", async function () {
      await assertFails(
        asAli()
          .collection("users")
          .doc(ALI)
          .set({ userType: "admin", updatedAt: new Date() }, { merge: true })
      );
    });

    it("A user cannot write an unknown field via set+merge", async function () {
      await assertFails(
        asAli()
          .collection("users")
          .doc(ALI)
          .set({ zzzBogus: 1 }, { merge: true })
      );
    });
  });
});
