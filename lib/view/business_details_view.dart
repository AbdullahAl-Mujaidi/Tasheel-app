import 'package:awesome_dialog/awesome_dialog.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fkra/controller/business_controller.dart';
import 'package:fkra/controller/team_members_controller.dart';
import 'package:fkra/controller/workers_controller.dart';
import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_api.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:flutter/material.dart';
import 'business_statement_view.dart';
import 'client_statement_view.dart';

class BusinessDetailsView extends StatefulWidget {
  final BusinessController controller;
  final String workId;

  const BusinessDetailsView({
    super.key,
    required this.controller,
    required this.workId,
  });

  @override
  State<BusinessDetailsView> createState() => _BusinessDetailsViewState();
}

class _BusinessDetailsViewState extends State<BusinessDetailsView> {
  static const List<String> _expenseCategories = [
    'اكل وشرب',
    'عمال',
    'معدات',
    'نقل ومواصلات',
    'مواد ومستلزمات',
    'اخرى',
  ];

  WorkersController? _workersCtrl;

  // حوار "مشاركة العمل": مشاركة عمل واحد مع مستخدم تابع (قراءة + تعديل).
  final TextEditingController _shareNameController = TextEditingController();
  final TextEditingController _shareEmailController = TextEditingController();
  bool _isSharing = false;

  Future<WorkersController> _ensureWorkers() async {
    _workersCtrl ??= WorkersController(userId: widget.controller.userId);
    await _workersCtrl!.ready;
    return _workersCtrl!;
  }

  @override
  void dispose() {
    _workersCtrl?.dispose();
    _shareNameController.dispose();
    _shareEmailController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? get _business {
    final String id = widget.workId;
    for (final b in widget.controller.businesses) {
      if (b['id'] != null && b['id'].toString() == id) return b;
    }
    return null;
  }

  /// سحب وضبط بيانات المشاركة ثم تنفيذها.
  Future<void> _showShareDialog(BuildContext context) async {
    _shareNameController.clear();
    _shareEmailController.clear();
    final formKey = GlobalKey<FormState>();
    await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مشاركة العمل'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'شارك هذا العمل مع مستخدم تابع: يحصل على عرض وتعديل '
                    'على هذا العمل فقط (لا يرى باقي أعمالك).',
                    style: TextStyle(
                        fontSize: 13, color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _shareNameController,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'الاسم',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().length < 3) {
                        return 'أدخل اسم المستخدم (3 أحرف على الأقل)';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _shareEmailController,
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'البريد الإلكتروني',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final value = v?.trim() ?? '';
                      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$')
                          .hasMatch(value)) {
                        return 'أدخل بريداً إلكترونياً صحيحاً';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: _isSharing
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      setState(() => _isSharing = true);
                      final String message;
                      try {
                        message = await _shareBusiness(
                          _shareNameController.text.trim(),
                          _shareEmailController.text.trim(),
                        );
                      } catch (e) {
                        setState(() => _isSharing = false);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(false);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .error,
                              content: Text(e.toString())));
                        }
                        return;
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop(true);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(message)));
                      }
                    },
              child: _isSharing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('مشاركة'),
            ),
          ],
        ),
      ),
    );
    // إعادة تعيين العلم بعد إغلاق الحوار (سواء نجحت المشاركة أو أُلغي).
    if (mounted && _isSharing) setState(() => _isSharing = false);
  }

  /// تنفيذ المشاركة: بحث عن مستخدم تابع قائم بالبريد، وإلا إنشاء حساب جديد
  /// (أو دعوة تفويض لبريد مسجّل مسبقاً) بصلاحيات مقصورة على العمل الحالي.
  Future<String> _shareBusiness(String name, String email) async {
    final ownerUid = widget.controller.userId;
    final cleanEmail = email.trim().toLowerCase();
    final workId = widget.workId;

    final myEmail =
        FirebaseAuth.instance.currentUser?.email?.trim().toLowerCase();
    if (cleanEmail == myEmail) {
      throw 'لا يمكن مشاركة العمل مع بريدك أنت';
    }

    final repo = TeamMemberRepository();
    final member = await repo.findSubUserByEmail(ownerUid, cleanEmail);
    if (member != null) {
      if (member.isPending) {
        await repo.addScopedIdToInvite(
            ownerUid: ownerUid, email: cleanEmail, workId: workId);
        return 'تمت مشاركة العمل مع $name — التفويض قيد التفعيل عند أول تسجيل دخول لصاحب البريد.';
      }
      if (member.canRead(TeamPermissions.businesses) &&
          member.canUpdate(TeamPermissions.businesses) &&
          !member.isScopedFor(TeamPermissions.businesses)) {
        return '$name يملك أصلاً وصولاً كاملاً إلى جميع أعمالك.';
      }
      await repo.grantScopedBusiness(
          ownerUid: ownerUid, memberUid: member.uid, workId: workId);
      return 'تمت مشاركة العمل مع $name.';
    }

    // لا يوجد عضو بهذا البريد: إنشاء حساب جديد (أو دعوة تفويض) مقيّد على العمل.
    // إن كانت توجد دعوة معلّقة من نفس المالك لهذا البريد (لم يُفَعِّل صاحبها
    // عضويته بعد) نُلحِق العمل بدل إنشاء دعوة جديدة كي لا تُضاعِف الإدخالات.
    final pending = await repo.findPendingInvite(ownerUid, cleanEmail);
    if (pending != null) {
      await repo.addScopedIdToInvite(
          ownerUid: ownerUid, email: cleanEmail, workId: workId);
      return 'تمت مشاركة العمل مع $name — التفويض قيد التفعيل عند أول تسجيل دخول لصاحب البريد.';
    }

    final tempPassword = TeamMembersController.generateTemporaryPassword();
    final permissions = TeamMember.permissionsForModules(const {});
    permissions[TeamPermissions.businesses] = {
      'read': true,
      'create': false,
      'update': true,
      'delete': false,
    };
    try {
      await MemberApi.instance.createSubUser(
        name: name,
        email: cleanEmail,
        temporaryPassword: tempPassword,
        permissions: permissions,
        scopedIds: {TeamPermissions.businesses: [workId]},
      );
      return 'تم إنشاء الحساب ومشاركة العمل مع $name.\n'
          'كلمة المرور المؤقتة: $tempPassword (تُغيَّر عند أول دخول).';
    } on MemberInviteSentException catch (e) {
      return '${e.message}\nوسيُشارَك العمل معه عند تفعيل التفويض.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final business = _business;
        if (business == null) {
          return Scaffold(
            appBar: AppBar(
              title: Text('تفاصيل العمل', style: TextStyle(color: colorScheme.primary)),
              centerTitle: true,
              backgroundColor: colorScheme.surface,
            ),
            body: Center(
              child: Text('العمل غير موجود',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
          );
        }

        final summary = widget.controller.calculateSummary(widget.workId);
        final transactions =
            widget.controller.getTransactionsForWork(widget.workId);

        return Scaffold(
          appBar: AppBar(
            title: Text(
              business['name'] ?? 'تفاصيل العمل',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.primary,
                fontSize: 20,
              ),
            ),
            centerTitle: true,
            backgroundColor: colorScheme.surface,
            elevation: 0,
            actions: [
              // مشاركة عمل واحد: للمالك فقط (لا تظهر لمستخدم مفوَّض).
              if (MemberSessionService.instance
                  .isActiveOwnerOf(widget.controller.userId))
                IconButton(
                  tooltip: 'مشاركة العمل',
                  icon: Icon(Icons.ios_share, color: colorScheme.primary),
                  onPressed: () => _showShareDialog(context),
                ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _buildStatusDateRow(business, colorScheme),
                      if ((business['createdByLabel'] ?? '')
                                  .toString()
                                  .isNotEmpty ||
                              (business['lastModifiedByLabel'] ?? '')
                                  .toString()
                                  .isNotEmpty)
                        _buildActorSection(business, colorScheme),
                      SizedBox(height: 10),
                      if ((business['description'] ?? '').toString().isNotEmpty)
                        _buildInfoCard(
                          'الوصف',
                          business['description'].toString(),
                          colorScheme,
                        ),
                      if (business['customFields'] is Map &&
                          (business['customFields'] as Map).isNotEmpty) ...[
                        SizedBox(height: 10),
                        _buildCustomFieldsCard(
                            Map<String, dynamic>.from(
                                business['customFields'] as Map),
                            colorScheme),
                      ],
                      SizedBox(height: 15),
                      Text(
                        'الملخص المالي',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      SizedBox(height: 8),
                      _buildSummaryGrid(summary, business, colorScheme),
                      SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'الحركات المالية',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${transactions.length} حركة',
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      if (transactions.isEmpty)
                        _buildEmptyTransactions(colorScheme)
                      else
                        ...transactions.map((tx) => _buildTransactionTile(
                            tx, colorScheme)),
                    ],
                  ),
                ),
              ),
              _buildBottomActions(colorScheme),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActorSection(
      Map<String, dynamic> business, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 10),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 4,
        children: [
          if ((business['createdByLabel'] ?? '').toString().isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_add_alt_1,
                    size: 15, color: colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  'أضيف بواسطة: ${business['createdByLabel']}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          if ((business['lastModifiedByLabel'] ?? '')
              .toString()
              .isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.edit, size: 15, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  'آخر تعديل: ${business['lastModifiedByLabel']}',
                  style: TextStyle(
                      fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildStatusDateRow(
      Map<String, dynamic> business, ColorScheme colorScheme) {
    String status = business['status'] ?? '';
    Color statusColor = colorScheme.primary;
    if (status == 'مكتمل') {
      statusColor = Colors.green;
    } else if (status == 'ملغي') {
      statusColor = colorScheme.error;
    } else if (status == 'جاري التنفيذ') {
      statusColor = Colors.orange;
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: TextStyle(
                    color: statusColor, fontWeight: FontWeight.bold)),
          ),
          Spacer(),
          Icon(Icons.event, size: 16, color: colorScheme.onSurfaceVariant),
          SizedBox(width: 4),
          Text(
            _formatDate(business['date']),
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
      String title, String content, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant)),
          SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(
                fontSize: 15, color: colorScheme.onSurface, height: 1.5),
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }

  Widget _buildCustomFieldsCard(
      Map<String, dynamic> customFieldsData, ColorScheme colorScheme) {
    final widgets = <Widget>[];
    customFieldsData.forEach((key, value) {
      if (value != null && value.toString().isNotEmpty) {
        widgets.add(Padding(
          padding: EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  _formatValue(value),
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 14),
                  textAlign: TextAlign.left,
                ),
              ),
              Text(
                key,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface),
              ),
            ],
          ),
        ));
      }
    });
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: widgets,
      ),
    );
  }

  Widget _buildSummaryGrid(
      Map<String, int> summary,
      Map<String, dynamic> business,
      ColorScheme colorScheme) {
    final int amount = (business['amount'] as num?)?.toInt() ?? 0;
    final int totalPaid = summary['totalPaid']!;
    final int totalExpenses = summary['totalExpenses']!;
    final int remaining = summary['remaining']!;

    final double boxWidth =
        (MediaQuery.of(context).size.width - 32) / 2;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('قيمة العمل', amount, colorScheme.primary,
              Icons.work_outline, colorScheme),
        ),
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('إجمالي الواصل', totalPaid, Colors.green,
              Icons.trending_down, colorScheme),
        ),
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('المتبقي', remaining,
              remaining == 0 ? Colors.green : Colors.orange,
              Icons.hourglass_empty, colorScheme),
        ),
        SizedBox(
          width: boxWidth,
          child: _buildSummaryBox('المصاريف', totalExpenses,
              colorScheme.error, Icons.remove_circle_outline, colorScheme),
        ),
      ],
    );
  }

  Widget _buildSummaryBox(String label, int value, Color color,
      IconData icon, ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: color, size: 20),
              SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              _formatAmount(value),
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          Text(
            'ريال',
            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTransactions(ColorScheme colorScheme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long,
              size: 40, color: colorScheme.onSurfaceVariant),
          SizedBox(height: 8),
          Text(
            'لا توجد حركات مالية بعد.\nأضف أول دفعة أو مصروف من الأسفل',
            textAlign: TextAlign.center,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTile(
      Map<String, dynamic> tx, ColorScheme colorScheme) {
    final bool isPayment = tx['type'] == 'payment';
    final Color color = isPayment ? Colors.green : colorScheme.error;
    final int amount = (tx['amount'] as num?)?.toInt() ?? 0;
    final String sign = isPayment ? '+' : '-';

    return Card(
      margin: EdgeInsets.symmetric(vertical: 4),
      color: colorScheme.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration:
                  BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
              child: Icon(
                isPayment ? Icons.arrow_downward : Icons.arrow_upward,
                color: color,
                size: 18,
              ),
            ),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    (tx['description'] ?? '').toString().isEmpty
                        ? (isPayment ? 'دفعة' : 'مصروف')
                        : tx['description'].toString(),
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface),
                    textAlign: TextAlign.right,
                  ),
                  SizedBox(height: 2),
                  Text(
                    _formatDate(tx['date']),
                    style: TextStyle(
                        fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  if ((tx['createdByLabel'] ?? '').toString().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        'بواسطة: ${tx['createdByLabel']}',
                        style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.right,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Text(
              '$sign${_formatAmount(amount)}',
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.bold, color: color),
            ),
            IconButton(
              onPressed: () => _confirmDeleteTransaction(context, tx),
              icon: Icon(Icons.delete_outline,
                  color: colorScheme.onSurfaceVariant, size: 20),
              tooltip: 'حذف الحركة',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActions(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddTransactionSheet(context, 'payment'),
                    icon: Icon(Icons.add, color: colorScheme.onPrimary, size: 18),
                    label: Text('إضافة دفعة',
                        style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, minimumSize: Size(0, 44)),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _showAddTransactionSheet(context, 'expense'),
                    icon: Icon(Icons.add, color: colorScheme.onPrimary, size: 18),
                    label: Text('إضافة مصروف',
                        style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        minimumSize: Size(0, 44)),
                  ),
                ),
              ],
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BusinessStatementView(
                            controller: widget.controller,
                            workId: widget.workId,
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.receipt_long, size: 18),
                    label: Text('كشف الحساب',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, 44),
                      side: BorderSide(color: colorScheme.primary, width: 1.5),
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClientStatementView(
                            controller: widget.controller,
                            workId: widget.workId,
                          ),
                        ),
                      );
                    },
                    icon: Icon(Icons.summarize, size: 18),
                    label: Text('كشف العميل',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, 44),
                      side: BorderSide(color: colorScheme.primary, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ========== إضافة دفعة / مصروف ==========
  Future<void> _showAddTransactionSheet(BuildContext context, String type) async {
    final bool isPayment = type == 'payment';
    final colorScheme = Theme.of(context).colorScheme;
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final descController = TextEditingController();
    DateTime selectedDate = DateTime.now();
    String selectedCategory = 'اخرى';
    String? selectedWorkerId;

    final workersCtrl = await _ensureWorkers();
    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Form(
                key: formKey,
                child: Container(
                  padding: EdgeInsets.all(15),
                  width: double.infinity,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Center(
                          child: Text(
                            isPayment ? 'إضافة دفعة' : 'إضافة مصروف',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface),
                          ),
                        ),
                        SizedBox(height: 20),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('المبلغ (ريال)',
                                      style: TextStyle(
                                          fontSize: 17,
                                          color: colorScheme.onSurface)),
                                  SizedBox(height: 8),
                                  TextFormField(
                                    controller: amountController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                        color: colorScheme.onSurface),
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return 'المبلغ مطلوب';
                                      }
                                      final amount =
                                          int.tryParse(value.trim());
                                      if (amount == null || amount <= 0) {
                                        return 'يرجى إدخال مبلغ صحيح أكبر من 0';
                                      }
                                      return null;
                                    },
                                    decoration: _inputDecoration(
                                        'مثال: 1000', colorScheme),
                                  ),
                                ],
                              ),
                            ),
                            if (!isPayment) ...[
                              SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.end,
                                  children: [
                                    Text('الفئة',
                                        style: TextStyle(
                                            fontSize: 17,
                                            color:
                                                colorScheme.onSurface)),
                                    SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      initialValue: selectedCategory,
                                      isExpanded: true,
                                      items: _expenseCategories
                                          .map((c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(
                                                  c,
                                                  style: TextStyle(
                                                      color: colorScheme
                                                          .onSurface),
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (value) =>
                                          setSheetState(() {
                                        selectedCategory = value ?? 'اخرى';
                                        if (selectedCategory != 'عمال') {
                                          selectedWorkerId = null;
                                        }
                                      }),
                                      style: TextStyle(
                                          color: colorScheme.onSurface),
                                      dropdownColor: colorScheme.surface,
                                      decoration: _inputDecoration(
                                          'اختر الفئة', colorScheme),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (!isPayment &&
                            selectedCategory == 'عمال') ...[
                          SizedBox(height: 15),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('اختر العامل',
                                  style: TextStyle(
                                      fontSize: 17,
                                      color: colorScheme.onSurface)),
                              SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                constraints:
                                    BoxConstraints(maxHeight: 220),
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  border: Border.all(
                                      color: colorScheme.outline),
                                ),
                                child:
                                    workersCtrl.workers.isEmpty
                                        ? Center(
                                            child: Text(
                                                'لا يوجد عمال مضافون',
                                                style: TextStyle(
                                                    color: colorScheme
                                                        .onSurfaceVariant)),
                                          )
                                        : ListView(
                                            shrinkWrap: true,
                                            children: workersCtrl.workers
                                                .map((w) {
                                              final String wId =
                                                  w['id']?.toString() ??
                                                      '';
                                              final bool selected =
                                                  selectedWorkerId ==
                                                      wId;
                                              return ListTile(
                                                dense: true,
                                                contentPadding:
                                                    EdgeInsets.zero,
                                                leading: Icon(
                                                  selected
                                                      ? Icons
                                                          .radio_button_checked
                                                      : Icons
                                                          .radio_button_unchecked,
                                                  color: colorScheme
                                                      .primary,
                                                ),
                                                title: Text(
                                                  w['name'] ?? '',
                                                  textAlign:
                                                      TextAlign.right,
                                                  style: TextStyle(
                                                      fontWeight:
                                                          FontWeight
                                                              .bold),
                                                ),
                                                onTap: () =>
                                                    setSheetState(() {
                                                      selectedWorkerId =
                                                          wId;
                                                    }),
                                              );
                                            }).toList(),
                                          ),
                              ),
                            ],
                          ),
                        ],
                        SizedBox(height: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('التفاصيل',
                                style: TextStyle(
                                    fontSize: 17,
                                    color: colorScheme.onSurface)),
                            SizedBox(height: 8),
                            TextFormField(
                              controller: descController,
                              textAlign: TextAlign.right,
                              style:
                                  TextStyle(color: colorScheme.onSurface),
                              maxLines: 2,
                              decoration: _inputDecoration(
                                  isPayment
                                      ? 'مثال: دفعة أولى من العميل'
                                      : 'مثال: شراء قطعة',
                                  colorScheme),
                            ),
                          ],
                        ),
                        SizedBox(height: 15),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('التاريخ',
                                style: TextStyle(
                                    fontSize: 17,
                                    color: colorScheme.onSurface)),
                            SizedBox(height: 8),
                            Container(
                              padding: EdgeInsets.all(10),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border:
                                    Border.all(color: colorScheme.outline),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    _formatDate(selectedDate),
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onSurface),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            colorScheme.primary),
                                    onPressed: () async {
                                      final DateTime? newDate =
                                          await showDatePicker(
                                        context: sheetContext,
                                        initialDate: selectedDate,
                                        firstDate: DateTime(1700),
                                        lastDate: DateTime(2200),
                                      );
                                      if (newDate != null) {
                                        setSheetState(() {
                                          selectedDate = newDate;
                                        });
                                      }
                                    },
                                    child: Text('اختر التاريخ',
                                        style: TextStyle(
                                            color: colorScheme.onPrimary,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 25),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton(
                              onPressed: () => Navigator.pop(sheetContext),
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.error),
                              child: Text('إلغاء',
                                  style: TextStyle(
                                      color: colorScheme.onError)),
                            ),
                            SizedBox(width: 15),
                            ElevatedButton(
                              onPressed: () async {
                                if (!formKey.currentState!.validate()) return;
                                final amount = int.tryParse(
                                        amountController.text.trim()) ??
                                    0;

                                if (!isPayment) {
                                  final bool isWorkerExpense =
                                      selectedCategory == 'عمال';
                                  if (isWorkerExpense &&
                                      selectedWorkerId == null) {
                                    ScaffoldMessenger.of(sheetContext)
                                        .showSnackBar(
                                      SnackBar(
                                          content: Text('يرجى اختيار العامل')),
                                    );
                                    return;
                                  }

                                  Map<String, dynamic>? worker;
                                  for (final w in workersCtrl.workers) {
                                    if (w['id']?.toString() ==
                                        selectedWorkerId) {
                                      worker = w;
                                      break;
                                    }
                                  }

                                  final String txId = DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString();
                                  final String note =
                                      descController.text.trim();
                                  final String businessName =
                                      _business?['name']?.toString() ?? '';
                                  final String txDesc =
                                      note.isEmpty ? selectedCategory : note;

                                  final String? wId = worker == null
                                      ? null
                                      : worker['id']?.toString();
                                  final String? wName = worker == null
                                      ? null
                                      : worker['name']?.toString();

                                  await widget.controller.addTransaction(
                                    workId: widget.workId,
                                    type: type,
                                    amount: amount,
                                    description: txDesc,
                                    date: selectedDate,
                                    category:
                                        _generalCategoryFor(selectedCategory),
                                    workerId:
                                        isWorkerExpense ? wId : null,
                                    workerName:
                                        isWorkerExpense ? wName : null,
                                    transactionId:
                                        isWorkerExpense ? txId : null,
                                  );

                                  if (isWorkerExpense && worker != null) {
                                    await workersCtrl.addWorkerExpense(
                                      worker['id'].toString(),
                                      amount: amount.toDouble(),
                                      description:
                                          'مصروف عمال - $businessName${note.isNotEmpty ? ' - $note' : ''}',
                                      expenseId: txId,
                                      linkToGeneral: false,
                                    );
                                  }
                                } else {
                                  await widget.controller.addTransaction(
                                    workId: widget.workId,
                                    type: type,
                                    amount: amount,
                                    description: descController.text.trim(),
                                    date: selectedDate,
                                  );
                                }
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(isPayment
                                          ? 'تمت إضافة الدفعة'
                                          : 'تمت إضافة المصروف'),
                                      backgroundColor: Colors.green,
                                    ),
                                  );
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: colorScheme.primary),
                              child: Text('حفظ',
                                  style: TextStyle(
                                      color: colorScheme.onPrimary)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  InputDecoration _inputDecoration(String hint, ColorScheme colorScheme) {
    return InputDecoration(
      filled: true,
      hintText: hint,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      fillColor: colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colorScheme.error),
      ),
    );
  }

  void _confirmDeleteTransaction(BuildContext context, Map<String, dynamic> tx) {
    AwesomeDialog(
      context: context,
      dialogType: DialogType.warning,
      animType: AnimType.bottomSlide,
      title: 'تأكيد الحذف',
      desc: 'هل تريد حذف هذه الحركة؟ سيتم إعادة حساب المبالغ تلقائياً.',
      btnOkText: 'حذف',
      btnCancelText: 'إلغاء',
      btnOkOnPress: () async {
        final bool isWorkerLinked =
            tx['type'] == 'expense' && tx['workerId'] != null;
        if (isWorkerLinked) {
          try {
            final workersCtrl = await _ensureWorkers();
            await workersCtrl.deleteWorkerExpenseById(tx['id'].toString());
          } catch (_) {}
        }
        await widget.controller
            .deleteTransaction(widget.workId, tx['id'].toString());
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('تم حذف الحركة بنجاح'),
                backgroundColor: Colors.green),
          );
        }
      },
    ).show();
  }

  String _generalCategoryFor(String label) {
    switch (label) {
      case 'اكل وشرب':
        return 'اكل ومشروبات';
      case 'معدات':
        return 'ادوات ومعدات';
      default:
        return label;
    }
  }

  // ========== دوال مساعدة ==========
  String _formatDate(dynamic date) {
    DateTime? d;
    if (date is DateTime) {
      d = date;
    } else if (date is String) {
      try {
        d = DateTime.parse(date);
      } catch (_) {}
    }
    if (d == null) return '';
    return '${d.day}-${d.month}-${d.year}';
  }

  String _formatValue(dynamic value) {
    if (value is DateTime) return '${value.day}-${value.month}-${value.year}';
    return value?.toString() ?? '';
  }

  String _formatAmount(num value) {
    final String s = value.toInt().toString();
    final StringBuffer buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      buf.write(s[i]);
      final int remaining = s.length - 1 - i;
      if (remaining > 0 && remaining % 3 == 0) buf.write(',');
    }
    return buf.toString();
  }
}