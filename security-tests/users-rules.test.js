const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require("@firebase/rules-unit-testing");

const fs = require("fs");

let testEnv;

describe("Firestore users security rules", function () {
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

      await db.collection("users").doc("userA").set({
        name: "Test User A",
        userType: "user",
      });

      await db.collection("users").doc("userB").set({
        name: "Test User B",
        userType: "user",
      });

      await db.collection("member_invites").doc("invite-userB").set({
        ownerUid: "userA",
        email: "abdullah@test.com",
        status: "active",
      });
    });
  });

  after(async function () {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  it("المستخدم A يستطيع قراءة ملفه الشخصي", async function () {
    const db = testEnv
      .authenticatedContext("userA")
      .firestore();

    await assertSucceeds(
      db.collection("users").doc("userA").get()
    );
  });

  it("المستخدم A لا يستطيع قراءة ملف المستخدم B", async function () {
    const db = testEnv
      .authenticatedContext("userA")
      .firestore();

    await assertFails(
      db.collection("users").doc("userB").get()
    );
  });

  it("المستخدم B لا يستطيع قراءة ملف المستخدم A", async function () {
    const db = testEnv
      .authenticatedContext("userB")
      .firestore();

    await assertFails(
      db.collection("users").doc("userA").get()
    );
  });

  it("المستخدم غير المسجل لا يستطيع قراءة ملف المستخدم A", async function () {
    const db = testEnv
      .unauthenticatedContext()
      .firestore();

    await assertFails(
      db.collection("users").doc("userA").get()
    );
  });

  it("المدير يستطيع قراءة ملف مستخدم آخر", async function () {
    const db = testEnv
      .authenticatedContext("adminUser", {
        role: "admin",
      })
      .firestore();

    await assertSucceeds(
      db.collection("users").doc("userB").get()
    );
  });

  it("المدير العادي لا يستطيع تغيير userType", async function () {
    const db = testEnv
      .authenticatedContext("adminUser", { role: "admin" })
      .firestore();

    await assertFails(
      db.collection("users").doc("userB").update({ userType: "admin" })
    );
  });

  it("المدير العادي لا يستطيع تغيير role أو علامة التفويض", async function () {
    const db = testEnv
      .authenticatedContext("adminUser", { role: "admin" })
      .firestore();

    await assertFails(
      db.collection("users").doc("userB").update({
        role: "admin",
        roleChangeAuthorizedBy: "adminUser",
      })
    );
  });

  it("المدير العادي يستطيع تحديث حقول التشغيل المسموحة فقط", async function () {
    const db = testEnv
      .authenticatedContext("adminUser", { role: "admin" })
      .firestore();

    await assertSucceeds(
      db.collection("users").doc("userB").update({ status: "active" })
    );
  });

  it("المدير العام يستطيع تغيير userType", async function () {
    const db = testEnv
      .authenticatedContext("superAdminUser", { role: "super_admin" })
      .firestore();

    await assertSucceeds(
      db.collection("users").doc("userB").update({
        userType: "admin",
        roleChangeAuthorizedBy: "superAdminUser",
      })
    );
  });

  it("العضو لا يستطيع منح نفسه صلاحيات إضافية عند إنشاء عضويته", async function () {
    const db = testEnv
      .authenticatedContext("userB", {
        email: "abdullah@test.com",
      })
      .firestore();

    await assertFails(
      db
        .collection("users")
        .doc("userA")
        .collection("team_members")
        .doc("userB")
        .set({
          uid: "userB",
          ownerUid: "userA",
          status: "active",
          role: "admin",
          permissions: {
            businesses: {
              read: true,
              create: true,
              update: true,
              delete: true,
            },
            workers: {
              read: true,
              create: true,
              update: true,
              delete: true,
            },
            expenses: {
              read: true,
              create: true,
              update: true,
              delete: true,
            },
          },
          scopedIds: {
            businesses: [
              "business1",
              "business2",
              "business3",
            ],
            workers: [
              "worker1",
              "worker2",
              "worker3",
            ],
          },
          inviteId: "invite-userB",
        })
    );
  });

  it(
    "المستخدم A لا يستطيع قراءة member_lookup الخاص بالمستخدم B",
    async function () {
      const db = testEnv
        .authenticatedContext("userA")
        .firestore();

      await assertFails(
        db
          .collection("member_lookups")
          .doc("userB")
          .get()
      );
    }
  );
  it("المستخدم A لا يستطيع تعديل member_lookup الخاص بالمستخدم B", async function () {
  const db = testEnv
    .authenticatedContext("userA")
    .firestore();

  await assertFails(
    db.collection("member_lookups").doc("userB").set({
      uid: "userB",
      ownerUid: "attackerOwner",
      email: "attacker@test.com",
    })
  );
  
});
it("المستخدم يستطيع قراءة member_lookup الخاص به", async function () {
  const db = testEnv
    .authenticatedContext("userB")
    .firestore();

  await assertSucceeds(
    db.collection("member_lookups").doc("userB").get()
  );
});
it(
  "المالك A لا يستطيع إنشاء member_lookup للمستخدم B",
  async function () {
    const db = testEnv
      .authenticatedContext("userA")
      .firestore();

    await assertFails(
      db.collection("member_lookups").doc("userB").set({
        uid: "userB",
        ownerUid: "userA",
        email: "userB@test.com",
        updatedAt: new Date(),
      })
    );
  }
);
it('المستخدم A يستطيع قراءة firebase_usage الخاص بالمستخدم B حاليًا', async () => {
  const dbA = testEnv.authenticatedContext('userA').firestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore()
      .collection('firebase_usage')
      .doc('userB')
      .set({
        uid: 'userB',
        reads: 100,
      });
  });

  await assertSucceeds(
    dbA.collection('firebase_usage').doc('userB').get()
  );
});

it('المستخدم A يستطيع تعديل firebase_usage الخاص بالمستخدم B حاليًا', async () => {
  const dbA = testEnv.authenticatedContext('userA').firestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore()
      .collection('firebase_usage')
      .doc('userB')
      .set({
        uid: 'userB',
        reads: 100,
      });
  });

  await assertSucceeds(
    dbA.collection('firebase_usage').doc('userB').update({
      reads: 999999,
    })
  );
});

it('المستخدم A يستطيع إنشاء firebase_usage باسم المستخدم B حاليًا', async () => {
  const dbA = testEnv.authenticatedContext('userA').firestore();

  await assertSucceeds(
    dbA.collection('firebase_usage').doc('userB').set({
      uid: 'userB',
      reads: 999999,
    })
  );
});
});