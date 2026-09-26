// lib/features/workers/data/models/worker_normalizer.dart
// تطبيع بيانات العامل: قيم افتراضية للحقول المتداخلة وتحويل القوائم المتداخلة
// (workRecords/payments/advances/workerExpenses) من أي مصدر إلى خرائط نظيفة.
// منقولة حرفياً من WorkersModel (المعالجتان اللتان كانتا خاصتين).
void applyWorkerDefaults(Map<String, dynamic> w) {
  w['wageType'] ??= 'monthly';
  w['status'] ??= 'active';
  w['workRecords'] ??= [];
  w['payments'] ??= [];
  w['advances'] ??= [];
  w['workerExpenses'] ??= [];
}

List<Map<String, dynamic>> castNestedList(dynamic raw) {
  if (raw == null) return [];
  if (raw is List) {
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  return [];
}