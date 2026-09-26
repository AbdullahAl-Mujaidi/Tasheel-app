import 'dart:convert';
import 'dart:io';

import 'package:fkra/db/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  String newUser() => 'u_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  test('حفظ وتحميل الأعمال مع customFields', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    final businesses = [
      {
        'id': 'b1',
        'name': 'مشروع أ',
        'description': 'وصف',
        'amount': 1000,
        'initialPaid': 200,
        'clientPhone': '0500000000',
        'totalPaid': 400,
        'totalExpenses': 50,
        'remaining': 600,
        'date': '2026-01-01T00:00:00.000',
        'status': 'قيد الانتظار',
        'customFields': {'animal': 'بقرة', 'count': 3},
        'synced': 0,
        'createdAt': '2026-01-01T00:00:00.000',
      }
    ];

    await db.saveAll('businesses', userId, businesses);
    final loaded = await db.loadAll('businesses', userId);

    expect(loaded.length, 1);
    expect(loaded.first['id'], 'b1');
    expect(loaded.first['name'], 'مشروع أ');
    expect(loaded.first['amount'], 1000);
    expect(loaded.first['initialPaid'], 200);
    expect(loaded.first['synced'], 0);
    expect(loaded.first['customFields'], {'animal': 'بقرة', 'count': 3});
  });

  test('حفظ قائمة فارغة يمسح صفوف المستخدم', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('businesses', userId, [
      {'id': 'b1', 'name': 'x'}
    ]);
    await db.saveAll('businesses', userId, []);
    expect(await db.loadAll('businesses', userId), isEmpty);
  });

  test('حفظ وتحميل الحركات', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('transactions', userId, [
      {
        'id': 't1',
        'workId': 'b1',
        'type': 'payment',
        'amount': 100,
        'description': 'دفعة',
        'category': 'اخرى',
        'date': '2026-01-02T00:00:00.000',
        'createdAt': '2026-01-02T00:00:00.000',
        'synced': 0,
        'workerId': 'w1',
        'workerName': 'عامل',
      }
    ]);
    final loaded = await db.loadAll('transactions', userId);
    expect(loaded.length, 1);
    expect(loaded.first['workId'], 'b1');
    expect(loaded.first['workerId'], 'w1');
  });

  test('حفظ وتحميل المصروفات مع القيم الاختيارية', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('expenses', userId, [
      {
        'id': 'e1',
        'description': 'شراء',
        'amount': 12.5,
        'category': 'مواد ومستلزمات',
        'date': '2026-01-03T00:00:00.000',
        'synced': 0,
        'createdAt': '2026-01-03T00:00:00.000',
        'source': 'business',
        'workId': 'b1',
        'workName': 'مشروع أ',
      },
      {
        'id': 'e2',
        'description': 'يدوي',
        'amount': 5,
        'category': 'اخرى',
        'date': '2026-01-04T00:00:00.000',
        'synced': 1,
        'createdAt': '2026-01-04T00:00:00.000',
      }
    ]);
    final loaded = await db.loadAll('expenses', userId);
    expect(loaded.length, 2);
    final e1 = loaded.firstWhere((e) => e['id'] == 'e1');
    expect(e1['amount'], 12.5);
    expect(e1['source'], 'business');
    final e2 = loaded.firstWhere((e) => e['id'] == 'e2');
    expect(e2['source'], isNull);
    expect(e2['workId'], isNull);
  });

  test('حفظ وتحميل العمال مع القوائم المتداخلة', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('workers', userId, [
      {
        'id': 'w1',
        'name': 'عامل 1',
        'phone': '0511111111',
        'specialization': 'بناء',
        'salary': 3000.0,
        'wageType': 'monthly',
        'date': '2026-01-01T00:00:00.000',
        'synced': 0,
        'createdAt': '2026-01-01T00:00:00.000',
        'status': 'active',
        'businessId': null,
        'workRecords': [
          {'id': 'r1', 'amount': 100, 'quantity': 2, 'unit': 'day'}
        ],
        'payments': [
          {'id': 'p1', 'amount': 50}
        ],
        'advances': [],
        'workerExpenses': [],
      }
    ]);
    final loaded = await db.loadAll('workers', userId);
    expect(loaded.length, 1);
    expect((loaded.first['workRecords'] as List).length, 1);
    expect(((loaded.first['workRecords'] as List).first)['amount'], 100);
    expect((loaded.first['payments'] as List).length, 1);
    expect(loaded.first['businessId'], isNull);
  });

  test('الحقول المخصصة: حفظ وتحميل كامل الكائن', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveCustomFields(userId, [
      {
        'id': 'f1',
        'fieldName': 'النوع',
        'fieldType': 'قائمة منسدلة',
        'isRequired': true,
        'defaultValue': 'أ',
        'options': ['أ', 'ب'],
        'userId': userId,
      }
    ]);
    final loaded = await db.loadCustomFields(userId);
    expect(loaded.length, 1);
    expect(loaded.first['fieldName'], 'النوع');
    expect(loaded.first['options'], ['أ', 'ب']);
    expect(loaded.first['isRequired'], true);
  });

  test('الكاش: خريطة وقائمة', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.setCache(userId, 'user_profile', {'fullName': 'أحمد'});
    expect((await db.getCache(userId, 'user_profile'))!['fullName'], 'أحمد');

    await db.setCacheList(userId, 'top_expenses', [
      {'id': 'e1', 'amount': 10}
    ]);
    final list = await db.getCacheList(userId, 'top_expenses');
    expect(list.length, 1);
    expect(list.first['amount'], 10);

    await db.removeCache(userId, 'user_profile');
    expect(await db.getCache(userId, 'user_profile'), isNull);
  });

  test('الترحيل من JSON إلى SQLite آمن ولا يتكرر', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    final dir = Directory.systemTemp.createTempSync('tasahel_mig_');
    final file = File('${dir.path}/businesses_$userId.json');
    await file.writeAsString(jsonEncode([
      {'id': 'b1', 'name': 'مرحّل', 'amount': 500, 'synced': 0}
    ]));

    await db.migrateJsonFile('businesses', userId, file.path);
    var loaded = await db.loadAll('businesses', userId);
    expect(loaded.length, 1);
    expect(loaded.first['name'], 'مرحّل');

    // تشغيل الترحيل مرة أخرى لا يضاعف البيانات
    await db.migrateJsonFile('businesses', userId, file.path);
    loaded = await db.loadAll('businesses', userId);
    expect(loaded.length, 1);

    // الملف الأصلي يبقى كما هو (نسخة احتياطية)
    expect(await file.exists(), true);

    dir.deleteSync(recursive: true);
  });

  test('الترحيل لا يستبدل بيانات موجودة مسبقًا', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('businesses', userId, [
      {'id': 'existing', 'name': 'موجود'}
    ]);

    final dir = Directory.systemTemp.createTempSync('tasahel_mig2_');
    final file = File('${dir.path}/businesses_$userId.json');
    await file.writeAsString(jsonEncode([
      {'id': 'b1', 'name': 'قديم'}
    ]));

    await db.migrateJsonFile('businesses', userId, file.path);
    final loaded = await db.loadAll('businesses', userId);
    expect(loaded.length, 1);
    expect(loaded.first['id'], 'existing');

    dir.deleteSync(recursive: true);
  });

  test('عزل المستخدمين في نفس القاعدة', () async {
    final userA = newUser();
    final userB = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('businesses', userA, [
      {'id': 'a1', 'name': 'أ'}
    ]);
    await db.saveAll('businesses', userB, [
      {'id': 'b1', 'name': 'ب'},
      {'id': 'b2', 'name': 'ب2'}
    ]);

    expect((await db.loadAll('businesses', userA)).length, 1);
    expect((await db.loadAll('businesses', userB)).length, 2);
    expect(
        (await db.loadAll('businesses', userB))
            .map((e) => e['id'])
            .toSet(),
        {'b1', 'b2'});
  });

  test('clearUserData يحذف كاش المستخدم والحقول ويبقي الأعمال', () async {
    final userId = newUser();
    final db = DatabaseHelper.instance;
    await db.saveAll('businesses', userId, [
      {'id': 'b1', 'name': 'يبقى'}
    ]);
    await db.setCache(userId, 'user_profile', {'fullName': 'أحمد'});
    await db.saveCustomFields(userId, [
      {'id': 'f1', 'fieldName': 'حقل'}
    ]);

    await db.clearUserData(userId);

    expect(await db.getCache(userId, 'user_profile'), isNull);
    expect(await db.loadCustomFields(userId), isEmpty);
    expect((await db.loadAll('businesses', userId)).length, 1);
  });
}

int _seq = 0;
