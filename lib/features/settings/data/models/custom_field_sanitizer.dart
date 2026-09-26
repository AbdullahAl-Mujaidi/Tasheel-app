// lib/features/settings/data/models/custom_field_sanitizer.dart
// تحويل قيم Timestamp/DateTime (أو قوائمها) إلى نصوص ISO حتى يمكن حفظها
// عبر jsonEncode. منقول حرفياً من SettingsModel._sanitizeCustomField.
import 'package:cloud_firestore/cloud_firestore.dart';

Map<String, dynamic> sanitizeCustomField(Map<String, dynamic> field) {
  final Map<String, dynamic> result = {};
  field.forEach((key, value) {
    if (value is Timestamp) {
      result[key] = value.toDate().toIso8601String();
    } else if (value is DateTime) {
      result[key] = value.toIso8601String();
    } else if (value is List) {
      result[key] = value.map((e) {
        if (e is Timestamp) return e.toDate().toIso8601String();
        if (e is DateTime) return e.toIso8601String();
        return e;
      }).toList();
    } else {
      result[key] = value;
    }
  });
  return result;
}