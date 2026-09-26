// lib/admin/models/admin_models.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'admin_role.dart';

DateTime _toDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
  return DateTime.now();
}

String _str(dynamic v, [String fallback = '-']) =>
    v == null ? fallback : v.toString();

/// عرض مبسّط للمستخدم لصفحة الإدارة (بدون أي بيانات مالية).
@immutable
class UserSnapshot {
  final String uid;
  final String fullName;
  final String email;
  final String businessName;
  final String phoneNumber;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;
  final DateTime? lastActivityAt;
  final DateTime? lastSyncAt;
  final String appVersion;
  final String lastLoginMethod;
  final String userType;
  final String status;
  final bool hasProfileDoc;

  const UserSnapshot({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.businessName,
    required this.phoneNumber,
    required this.createdAt,
    required this.lastLoginAt,
    required this.lastActivityAt,
    required this.lastSyncAt,
    required this.appVersion,
    required this.lastLoginMethod,
    required this.userType,
    required this.status,
    required this.hasProfileDoc,
  });

  factory UserSnapshot.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return UserSnapshot(
      uid: doc.id,
      fullName: _str(d['fullName'], doc.id),
      email: _str(d['email']),
      businessName: _str(d['businessName']),
      phoneNumber: _str(d['phoneNumber']),
      createdAt: d['createdAt'] != null ? _toDate(d['createdAt']) : null,
      lastLoginAt: d['lastLoginAt'] != null ? _toDate(d['lastLoginAt']) : null,
      lastActivityAt:
          d['lastActivityAt'] != null ? _toDate(d['lastActivityAt']) : null,
      lastSyncAt: d['lastSyncAt'] != null ? _toDate(d['lastSyncAt']) : null,
      appVersion: _str(d['appVersion']),
      lastLoginMethod: _str(d['lastLoginMethod']),
      userType: _str(d['userType'], 'user'),
      status: _str(d['status'], 'active'),
      hasProfileDoc: (d as Map).isNotEmpty,
    );
  }

  bool get isAdmin => userType == 'admin' || userType == 'super_admin' || email.trim().toLowerCase() == 'abdullahalmjudi@gmail.com';
  bool get isSuperAdmin => userType == 'super_admin' || email.trim().toLowerCase() == 'abdullahalmjudi@gmail.com';
  bool get isBlocked => status == 'blocked' || status == 'suspended';
  bool get isSuspended => status == 'suspended' || status == 'blocked';

  String get roleLabel {
    if (email.trim().toLowerCase() == 'abdullahalmjudi@gmail.com' || userType == 'super_admin') {
      return 'مدير عام';
    }
    switch (userType) {
      case 'admin':
        return 'مدير';
      case 'analyst':
        return 'محلل';
      default:
        return 'مستخدم';
    }
  }

  UserSnapshot copyWith({
    String? fullName,
    String? email,
    String? businessName,
    String? phoneNumber,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    DateTime? lastActivityAt,
    DateTime? lastSyncAt,
    String? appVersion,
    String? lastLoginMethod,
    String? userType,
    String? status,
    bool? hasProfileDoc,
  }) {
    return UserSnapshot(
      uid: uid,
      fullName: fullName ?? this.fullName,
      email: email ?? this.email,
      businessName: businessName ?? this.businessName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      lastActivityAt: lastActivityAt ?? this.lastActivityAt,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      appVersion: appVersion ?? this.appVersion,
      lastLoginMethod: lastLoginMethod ?? this.lastLoginMethod,
      userType: userType ?? this.userType,
      status: status ?? this.status,
      hasProfileDoc: hasProfileDoc ?? this.hasProfileDoc,
    );
  }
}

/// عدادات مؤلفة من Cloud Function (عدد الأعمال فقط - بدون تفاصيل مالية).
@immutable
class UserCounts {
  final String uid;
  final int businessCount;
  final int completedCount;
  final int inProgressCount;

  const UserCounts({
    required this.uid,
    required this.businessCount,
    required this.completedCount,
    required this.inProgressCount,
  });

  factory UserCounts.empty(String uid) =>
      UserCounts(uid: uid, businessCount: 0, completedCount: 0, inProgressCount: 0);

  factory UserCounts.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return UserCounts(
      uid: doc.id,
      businessCount: (d['businessCount'] as num?)?.toInt() ?? 0,
      completedCount: (d['completedCount'] as num?)?.toInt() ?? 0,
      inProgressCount: (d['inProgressCount'] as num?)?.toInt() ?? 0,
    );
  }
}

@immutable
class AdminMember {
  final String uid;
  final String email;
  final String displayName;
  final AdminRole? role;
  final String status;
  final bool protected;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  const AdminMember({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.status,
    required this.protected,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory AdminMember.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AdminMember(
      uid: doc.id,
      email: _str(d['email']),
      displayName: _str(d['displayName'], doc.id),
      role: AdminRole.tryParse(d['role']),
      status: _str(d['status'], 'active'),
      protected: d['protected'] == true,
      createdAt: d['createdAt'] != null ? _toDate(d['createdAt']) : null,
      lastLoginAt: d['lastLoginAt'] != null ? _toDate(d['lastLoginAt']) : null,
    );
  }
}

@immutable
class AuditLogEntry {
  final String id;
  final String actorUid;
  final String actorEmail;
  final String action;
  final String result;
  final Map<String, dynamic> details;
  final DateTime timestamp;

  const AuditLogEntry({
    required this.id,
    required this.actorUid,
    required this.actorEmail,
    required this.action,
    required this.result,
    required this.details,
    required this.timestamp,
  });

  factory AuditLogEntry.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return AuditLogEntry(
      id: doc.id,
      actorUid: _str(d['actorUid']),
      actorEmail: _str(d['actorEmail']),
      action: _str(d['action']),
      result: _str(d['result']),
      details: Map<String, dynamic>.from(d['details'] as Map? ?? {}),
      timestamp: d['timestamp'] != null ? _toDate(d['timestamp']) : DateTime.now(),
    );
  }

  String get actionLabel {
    switch (action) {
      case 'admin_role_set':
        return 'تعيين دور مدير';
      case 'admin_role_removed':
        return 'إزالة مدير';
      case 'user_promoted_admin':
        return 'ترقية مستخدم إلى مدير';
      case 'user_demoted':
        return 'إلغاء صلاحية مدير';
      case 'user_blocked':
        return 'تعليق حساب';
      case 'user_unblocked':
        return 'إلغاء تعليق حساب';
      case 'user_deleted':
        return 'حذف حساب';
      case 'notification_send':
        return 'إرسال إشعار';
      case 'platform_config_updated':
        return 'تعديل إعدادات المنصة';
      case 'stats_refresh':
        return 'تحديث الإحصائيات';
      default:
        return action;
    }
  }
}

@immutable
class NotificationRequest {
  final String id;
  final String title;
  final String body;
  final String targetType;
  final String? targetUid;
  final String status;
  final int sentCount;
  final int failureCount;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? finishedAt;

  const NotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.targetType,
    required this.targetUid,
    required this.status,
    required this.sentCount,
    required this.failureCount,
    required this.createdBy,
    required this.createdAt,
    required this.finishedAt,
  });

  factory NotificationRequest.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return NotificationRequest(
      id: doc.id,
      title: _str(d['title']),
      body: _str(d['body']),
      targetType: _str(d['targetType'], 'all'),
      targetUid: d['targetUid']?.toString(),
      status: _str(d['status'], 'pending'),
      sentCount: (d['sentCount'] as num?)?.toInt() ?? 0,
      failureCount: (d['failureCount'] as num?)?.toInt() ?? 0,
      createdBy: _str(d['createdBy']),
      createdAt: d['createdAt'] != null ? _toDate(d['createdAt']) : DateTime.now(),
      finishedAt: d['finishedAt'] != null ? _toDate(d['finishedAt']) : null,
    );
  }

  String get statusLabel {
    switch (status) {
      case 'pending':
        return 'قيد الإرسال';
      case 'sent':
        return 'مكتمل';
      case 'sent_with_errors':
        return 'فشل جزئي';
      case 'failed':
        return 'فشل';
      case 'no_devices':
        return 'لا توجد أجهزة';
      default:
        return status;
    }
  }
}

@immutable
class AppConfig {
  final String appName;
  final String currentVersion;
  final String minVersion;
  final bool forceUpdate;
  final String updateUrl;
  final String releaseNotes;
  final bool notificationsEnabled;

  const AppConfig({
    required this.appName,
    required this.currentVersion,
    required this.minVersion,
    required this.forceUpdate,
    required this.updateUrl,
    required this.releaseNotes,
    required this.notificationsEnabled,
  });

  static const defaultConfig = AppConfig(
    appName: 'تسهيل',
    currentVersion: '',
    minVersion: '',
    forceUpdate: false,
    updateUrl: '',
    releaseNotes: '',
    notificationsEnabled: true,
  );

  factory AppConfig.fromDoc(DocumentSnapshot? doc) {
    final d = doc?.data() as Map<String, dynamic>? ?? {};
    return AppConfig(
      appName: _str(d['appName'], defaultConfig.appName),
      currentVersion: _str(d['currentVersion'], ''),
      minVersion: _str(d['minVersion'], ''),
      forceUpdate: d['forceUpdate'] == true,
      updateUrl: _str(d['updateUrl'], ''),
      releaseNotes: _str(d['releaseNotes'], ''),
      notificationsEnabled: d['notificationsEnabled'] != false,
    );
  }
}

@immutable
class DashboardStats {
  final int totalUsers;
  final int newUsers7;
  final int newUsers30;
  final int activeUsers7;
  final int activeUsers30;
  final int totalBusinesses;
  final int completedBusinesses;
  final int inProgressBusinesses;

  /// أعمال أُنشئت خلال اليوم الحالي (اليوم التقويمي).
  final int businessesToday;

  /// كل الأعمال غير المكتملة (إجمالي - مكتملة).
  final int remainingBusinesses;

  /// إجمالي العمال المسجلين عبر كل الحسابات.
  final int totalWorkers;

  final Map<String, int> versionDistribution;
  final DateTime? statsUpdatedAt;

  const DashboardStats({
    required this.totalUsers,
    required this.newUsers7,
    required this.newUsers30,
    required this.activeUsers7,
    required this.activeUsers30,
    required this.totalBusinesses,
    required this.completedBusinesses,
    required this.inProgressBusinesses,
    this.businessesToday = 0,
    this.remainingBusinesses = 0,
    this.totalWorkers = 0,
    required this.versionDistribution,
    required this.statsUpdatedAt,
  });

  factory DashboardStats.fromDoc(DocumentSnapshot? doc) {
    final d = doc?.data() as Map<String, dynamic>? ?? {};
    final versions = d['versionDistribution'] as Map? ?? {};
    final totalBusinesses = (d['totalBusinesses'] as num?)?.toInt() ?? 0;
    final completedBusinesses = (d['completedBusinesses'] as num?)?.toInt() ?? 0;
    return DashboardStats(
      totalUsers: (d['totalUsers'] as num?)?.toInt() ?? 0,
      newUsers7: (d['newUsers7'] as num?)?.toInt() ?? 0,
      newUsers30: (d['newUsers30'] as num?)?.toInt() ?? 0,
      activeUsers7: (d['activeUsers7'] as num?)?.toInt() ?? 0,
      activeUsers30: (d['activeUsers30'] as num?)?.toInt() ?? 0,
      totalBusinesses: totalBusinesses,
      completedBusinesses: completedBusinesses,
      inProgressBusinesses: (d['inProgressBusinesses'] as num?)?.toInt() ?? 0,
      businessesToday: (d['businessesToday'] as num?)?.toInt() ?? 0,
      remainingBusinesses: (d['remainingBusinesses'] as num?)?.toInt() ?? (totalBusinesses - completedBusinesses),
      totalWorkers: (d['totalWorkers'] as num?)?.toInt() ?? 0,
      versionDistribution: versions.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      statsUpdatedAt:
          d['statsUpdatedAt'] != null ? _toDate(d['statsUpdatedAt']) : null,
    );
  }
}