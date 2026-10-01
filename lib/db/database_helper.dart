// ignore_for_file: avoid_print
// lib/db/database_helper.dart
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// قاعدة SQLite الموحدة للتخزين المحلي.
///
/// جميع البيانات تُخزَّن بعمود user_id لعزل المستخدمين في قاعدة واحدة.
/// أسماء الأعمدة بنفس مفاتيح JSON الحالية (camelCase) حتى تعود الصفوف
/// كما كانت تُقرأ من الملفات مباشرة دون أي تعيين بين المفاتيح.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const String dbFileName = 'tasahel.db';

  // أعمدة كل جدول بنفس مفاتيح JSON الحالية (بدون عمود user_id).
  static const Map<String, List<String>> _columns = {
    'businesses': <String>[
      'id',
      'name',
      'description',
      'amount',
      'initialPaid',
      'clientPhone',
      'totalPaid',
      'totalExpenses',
      'remaining',
      'date',
      'status',
      'customFields',
      'synced',
      'createdAt',
      'createdByLabel',
      'createdByRole',
      'createdByUid',
      'lastModifiedByLabel',
      'lastModifiedByRole',
      'lastModifiedByUid',
    ],
    'transactions': <String>[
      'id',
      'workId',
      'type',
      'amount',
      'description',
      'category',
      'date',
      'createdAt',
      'synced',
      'workerId',
      'workerName',
      'createdByLabel',
      'createdByRole',
      'createdByUid',
      'lastModifiedByLabel',
      'lastModifiedByRole',
      'lastModifiedByUid',
    ],
    'expenses': <String>[
      'id',
      'description',
      'amount',
      'category',
      'date',
      'synced',
      'createdAt',
      'source',
      'workId',
      'workName',
      'workerId',
      'workerName',
      'createdByLabel',
      'createdByRole',
      'createdByUid',
      'lastModifiedByLabel',
      'lastModifiedByRole',
      'lastModifiedByUid',
    ],
    'workers': <String>[
      'id',
      'name',
      'phone',
      'specialization',
      'salary',
      'wageType',
      'date',
      'synced',
      'createdAt',
      'status',
      'businessId',
      'workRecords',
      'payments',
      'advances',
      'workerExpenses',
      'createdByLabel',
      'createdByRole',
      'createdByUid',
      'lastModifiedByLabel',
      'lastModifiedByRole',
      'lastModifiedByUid',
    ],
  };

  // الأعمدة التي قيمها JSON (خريطة/قائمة).
  static const Map<String, Set<String>> _jsonColumns = {
    'businesses': {'customFields'},
    'workers': {'workRecords', 'payments', 'advances', 'workerExpenses'},
  };

  Future<Database>? _dbFuture;

  Future<Database> get database => _dbFuture ??= _open();

  Future<Database> _open() async {
    final String dir = await getDatabasesPath();
    final String dbPath = p.join(dir, dbFileName);
    return openDatabase(
      dbPath,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE businesses (
            user_id TEXT NOT NULL,
            id TEXT NOT NULL,
            name TEXT,
            description TEXT,
            amount INTEGER,
            initialPaid INTEGER,
            clientPhone TEXT,
            totalPaid INTEGER,
            totalExpenses INTEGER,
            remaining INTEGER,
            date TEXT,
            status TEXT,
            customFields TEXT,
            synced INTEGER,
            createdAt TEXT,
            createdByLabel TEXT,
            createdByRole TEXT,
            createdByUid TEXT,
            lastModifiedByLabel TEXT,
            lastModifiedByRole TEXT,
            lastModifiedByUid TEXT,
            PRIMARY KEY (user_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE transactions (
            user_id TEXT NOT NULL,
            id TEXT NOT NULL,
            workId TEXT,
            type TEXT,
            amount INTEGER,
            description TEXT,
            category TEXT,
            date TEXT,
            createdAt TEXT,
            synced INTEGER,
            workerId TEXT,
            workerName TEXT,
            createdByLabel TEXT,
            createdByRole TEXT,
            createdByUid TEXT,
            lastModifiedByLabel TEXT,
            lastModifiedByRole TEXT,
            lastModifiedByUid TEXT,
            PRIMARY KEY (user_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses (
            user_id TEXT NOT NULL,
            id TEXT NOT NULL,
            description TEXT,
            amount REAL,
            category TEXT,
            date TEXT,
            synced INTEGER,
            createdAt TEXT,
            source TEXT,
            workId TEXT,
            workName TEXT,
            workerId TEXT,
            workerName TEXT,
            createdByLabel TEXT,
            createdByRole TEXT,
            createdByUid TEXT,
            lastModifiedByLabel TEXT,
            lastModifiedByRole TEXT,
            lastModifiedByUid TEXT,
            PRIMARY KEY (user_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE workers (
            user_id TEXT NOT NULL,
            id TEXT NOT NULL,
            name TEXT,
            phone TEXT,
            specialization TEXT,
            salary REAL,
            wageType TEXT,
            date TEXT,
            synced INTEGER,
            createdAt TEXT,
            status TEXT,
            businessId TEXT,
            workRecords TEXT,
            payments TEXT,
            advances TEXT,
            workerExpenses TEXT,
            createdByLabel TEXT,
            createdByRole TEXT,
            createdByUid TEXT,
            lastModifiedByLabel TEXT,
            lastModifiedByRole TEXT,
            lastModifiedByUid TEXT,
            PRIMARY KEY (user_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE custom_fields (
            user_id TEXT NOT NULL,
            id TEXT NOT NULL,
            data TEXT,
            PRIMARY KEY (user_id, id)
          )
        ''');
        await db.execute('''
          CREATE TABLE app_cache (
            user_id TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT,
            updatedAt TEXT,
            PRIMARY KEY (user_id, key)
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          const attributionCols = <String>[
            'createdByLabel',
            'createdByRole',
            'createdByUid',
            'lastModifiedByLabel',
            'lastModifiedByRole',
            'lastModifiedByUid',
          ];
          for (final table in const [
            'businesses',
            'transactions',
            'expenses',
            'workers',
          ]) {
            for (final col in attributionCols) {
              try {
                await db.execute(
                    'ALTER TABLE $table ADD COLUMN $col TEXT');
              } catch (_) {}
            }
          }
        }
      },
    );
  }

  // ========== حفظ قائمة كاملة (تعادل كتابة الملف كاملاً) ==========
  Future<void> saveAll(
      String table, String userId, List<Map<String, dynamic>> items) async {
    final db = await database;
    final List<String> columns = _columns[table] ?? const <String>[];
    final Set<String> jsonCols = _jsonColumns[table] ?? const <String>{};
    await db.transaction((txn) async {
      await txn.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      if (items.isEmpty) return;
      final batch = txn.batch();
      for (final item in items) {
        final List<String> rowCols = ['user_id'];
        final List<Object?> rowVals = [userId];
        for (final col in columns) {
          if (!item.containsKey(col)) continue;
          dynamic v = item[col];
          if (jsonCols.contains(col) && v != null) {
            v = jsonEncode(v);
          }
          rowCols.add(col);
          rowVals.add(v);
        }
        batch.insert(
          table,
          Map.fromIterables(rowCols, rowVals),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // ========== تحميل قائمة كاملة ==========
  Future<List<Map<String, dynamic>>> loadAll(
      String table, String userId) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      table,
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final Set<String> jsonCols = _jsonColumns[table] ?? const <String>{};
    final List<Map<String, dynamic>> result = [];
    for (final row in rows) {
      final Map<String, dynamic> m = Map<String, dynamic>.from(row);
      m.remove('user_id');
      for (final col in jsonCols) {
        final dynamic v = m[col];
        if (v is String) {
          try {
            m[col] = jsonDecode(v);
          } catch (_) {
            // تبقى القيمة نصاً إن لم تكن JSON صالحة
          }
        }
      }
      result.add(m);
    }
    return result;
  }

  // ========== ترحيل ملف JSON إلى جدول كيان (idempotent وآمن) ==========
  Future<void> migrateJsonFile(
      String table, String userId, String jsonPath) async {
    final File file = File(jsonPath);
    if (!await file.exists()) return;
    final db = await database;
    final int count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM $table WHERE user_id = ?',
          [userId],
        )) ??
        0;
    if (count > 0) return; // مُرحَّل مسبقاً
    try {
      final String jsonString = await file.readAsString();
      final List<dynamic> list = jsonDecode(jsonString);
      final items = list
          .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await saveAll(table, userId, items);
    } catch (e) {
      print('خطأ في ترحيل $table للمستخدم $userId: $e');
    }
  }

  // ========== الحقول المخصصة ==========
  Future<void> saveCustomFields(
      String userId, List<Map<String, dynamic>> fields) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('custom_fields',
          where: 'user_id = ?', whereArgs: [userId]);
      if (fields.isEmpty) return;
      final batch = txn.batch();
      for (final f in fields) {
        batch.insert(
          'custom_fields',
          {
            'user_id': userId,
            'id': f['id']?.toString() ?? '',
            'data': jsonEncode(f),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Map<String, dynamic>>> loadCustomFields(
      String userId) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'custom_fields',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
    final List<Map<String, dynamic>> result = [];
    for (final row in rows) {
      final dynamic data = row['data'];
      if (data is String) {
        try {
          result.add(Map<String, dynamic>.from(jsonDecode(data) as Map));
        } catch (_) {
          // تجاهل الصف غير الصالح
        }
      }
    }
    return result;
  }

  Future<void> migrateCustomFieldsJsonFile(
      String userId, String jsonPath) async {
    final File file = File(jsonPath);
    if (!await file.exists()) return;
    final db = await database;
    final int count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM custom_fields WHERE user_id = ?',
          [userId],
        )) ??
        0;
    if (count > 0) return;
    try {
      final String jsonString = await file.readAsString();
      final List<dynamic> list = jsonDecode(jsonString);
      final fields = list
          .map<Map<String, dynamic>>(
              (e) => Map<String, dynamic>.from(e as Map))
          .toList();
      await saveCustomFields(userId, fields);
    } catch (e) {
      print('خطأ في ترحيل custom_fields للمستخدم $userId: $e');
    }
  }

  // ========== الكاش العام (بيانات المستخدم / الإحصائيات) ==========
  Future<Map<String, dynamic>?> getCache(String userId, String key) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'app_cache',
      where: 'user_id = ? AND key = ?',
      whereArgs: [userId, key],
    );
    if (rows.isEmpty) return null;
    final dynamic v = rows.first['value'];
    if (v is String) {
      try {
        return Map<String, dynamic>.from(jsonDecode(v) as Map);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<List<Map<String, dynamic>>> getCacheList(
      String userId, String key) async {
    final db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'app_cache',
      where: 'user_id = ? AND key = ?',
      whereArgs: [userId, key],
    );
    if (rows.isEmpty) return [];
    final dynamic v = rows.first['value'];
    if (v is String) {
      try {
        final dynamic decoded = jsonDecode(v);
        if (decoded is List) {
          return decoded
              .map<Map<String, dynamic>>(
                  (e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      } catch (_) {
        return [];
      }
    }
    return [];
  }

  Future<void> setCache(String userId, String key,
      Map<String, dynamic> value) async {
    final db = await database;
    await db.insert(
      'app_cache',
      {
        'user_id': userId,
        'key': key,
        'value': jsonEncode(value),
        'updatedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> setCacheList(String userId, String key,
      List<Map<String, dynamic>> value) async {
    final db = await database;
    await db.insert(
      'app_cache',
      {
        'user_id': userId,
        'key': key,
        'value': jsonEncode(value),
        'updatedAt': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> removeCache(String userId, String key) async {
    final db = await database;
    await db.delete(
      'app_cache',
      where: 'user_id = ? AND key = ?',
      whereArgs: [userId, key],
    );
  }

  // ترحيل ملف JSON إلى الكاش (خريطة أو قائمة)
  Future<void> migrateJsonToCache(
      String userId, String key, String jsonPath) async {
    final File file = File(jsonPath);
    if (!await file.exists()) return;
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
          'SELECT COUNT(*) FROM app_cache WHERE user_id = ? AND key = ?',
          [userId, key],
        )) ??
        0;
    if (count > 0) return;
    try {
      final String jsonString = await file.readAsString();
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is Map) {
        await setCache(userId, key, Map<String, dynamic>.from(decoded));
      } else if (decoded is List) {
        await setCacheList(
            userId,
            key,
            decoded
                .map<Map<String, dynamic>>(
                    (e) => Map<String, dynamic>.from(e as Map))
                .toList());
      }
    } catch (e) {
      print('خطأ في ترحيل الكاش $key للمستخدم $userId: $e');
    }
  }

  // ========== تنظيف بيانات المستخدم ==========
  // يحاكي clearAllLocalData الحالي: يحذف كاش المستخدم والحقول المخصصة فقط
  // مع إبقاء الأعمال/الحركات/المصروفات/العمال (كما كان سلوك الملفات).
  Future<void> clearUserData(String userId) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('custom_fields',
          where: 'user_id = ?', whereArgs: [userId]);
      await txn.delete('app_cache',
          where: 'user_id = ? AND key = ?', whereArgs: [userId, 'user_profile']);
    });
  }

  /// كل الجداول التي تحمل بيانات مستخدم (الجميع مفهرس بـ user_id).
  static const List<String> _userScopedTables = [
    'transactions',
    'expenses',
    'workers',
    'businesses',
    'custom_fields',
    'app_cache',
  ];

  /// حذف *كامل* لكل بيانات [userIds] من قاعدة البيانات المحلية.
  ///
  /// الفرق عن `clearUserData`: هذا يمسح الأعمال والحركات والمصروفات والعمال
  /// وكاش التطبيق، لا الحقول المخصصة فقط — وهو المطلوب عند حذف الحساب.
  ///
  /// لماذا نمرّر قائمة معرّفات وليس معرّفاً واحداً؟ لأن صفوف تفويض المستخدم
  /// (delegate) مخزَّنة محلياً تحت `user_id` المالك الذي يعرض بياناته. فحذف
  /// الحساب يجب أن يمسح تلك السطور أيضاً عن هذا الجهاز: بعد الحذف لم يعد
  /// المستخدم مخوَّلاً أصلاً برؤية بيانات المالك، وإبقاؤها محلياً تسريب.
  /// ملاحظة: هذا لا يمسّ بيانات المالك على سحابة/جهازه — التنظيف هنا محلي
  /// على جهاز الحساب المحذوف فقط.
  Future<void> purgeUserData(List<String> userIds) async {
    final ids = userIds.where((id) => id.trim().isNotEmpty).toSet();
    if (ids.isEmpty) return;

    final db = await database;
    final args = ids.toList();
    final placeholders = List.filled(args.length, '?').join(', ');

    await db.transaction((txn) async {
      for (final table in _userScopedTables) {
        await txn.delete(table,
            where: 'user_id IN ($placeholders)', whereArgs: args);
      }
    });
    print('تم حذف بيانات المستخدم محلياً من ${_userScopedTables.length} جداول: $ids');
  }
}