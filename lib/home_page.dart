import 'package:fkra/model/team_member_model.dart';
import 'package:fkra/services/member_session_service.dart';
import 'package:fkra/view/business_view.dart';
import 'package:fkra/view/expense_view.dart';
import 'package:fkra/view/home_view.dart';
import 'package:fkra/view/member_settings_view.dart';
import 'package:fkra/view/report_view.dart';
import 'package:fkra/view/settings_view.dart';
import 'package:fkra/view/workers_view.dart';
import 'package:flutter/material.dart';

class Homepage extends StatefulWidget {
  /// معرّف البيانات = صاحب الحساب (ownerUid). للمستخدم التابع تُمرَّر له هنا
  /// بيانات المالك حتى تصل كل الموديلات إلى مسار users/{ownerUid}.
  final String userId;

  /// يعبأ فقط إذا كان المستخدم الحالي تابعاً (لإظهار تبويبات حسب الصلاحيات).
  final String? memberUid;
  const Homepage({super.key, required this.userId, this.memberUid});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  static final GlobalKey<_HomepageState> homePageKey = GlobalKey();

  int selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    MemberSessionService.instance.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    MemberSessionService.instance.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void changePage(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  String get _activeUserId {
    final sessionOwner = MemberSessionService.instance.ownerUid;
    if (sessionOwner.isNotEmpty) return sessionOwner;
    return widget.userId;
  }

  String? get _activeMemberUid {
    if (MemberSessionService.instance.isSubUser) {
      return MemberSessionService.instance.authUid;
    }
    return widget.memberUid;
  }

  bool get _isMember => _activeMemberUid != null;

  bool _canRead(String module) {
    if (!_isMember) return true;
    final member = MemberSessionService.instance.member;
    if (member == null) return false;
    return member.canRead(module);
  }

  List<Widget> _buildPages() {
    final userId = _activeUserId;
    final memberUid = _activeMemberUid;

    final pages = <Widget>[];
    // الرئيسية خاصة بالمالك فقط — التابع يعمل على بيانات المالك من التبويبات
    // المُصرَّح له بها فقط ولا يرى لوحة الإحصائيات العامة.
    if (!_isMember) {
      pages.add(HomePage(
          key: ValueKey('home_$userId'), changePage: changePage, userId: userId));
    }
    if (_canRead(TeamPermissions.businesses)) {
      pages.add(BusinessPage(key: ValueKey('business_$userId'), userId: userId));
    }
    if (_canRead(TeamPermissions.workers)) {
      pages.add(WorkersPage(key: ValueKey('workers_$userId'), userId: userId));
    }
    if (_canRead(TeamPermissions.expenses)) {
      pages.add(ExpensesPage(key: ValueKey('expenses_$userId'), userId: userId));
    }
    if (_canRead(TeamPermissions.reports)) {
      pages.add(ReportsPage(key: ValueKey('reports_$userId'), userId: userId));
    }
    pages.add(_isMember
        ? MemberSettingsPage(key: ValueKey('member_settings_$userId'), userId: userId, memberUid: memberUid!)
        : SettingsPage(key: ValueKey('settings_$userId'), userId: userId));
    return pages;
  }

  List<BottomNavigationBarItem> _buildTabs() {
    final isMember = _isMember;
    final items = <BottomNavigationBarItem>[];
    if (!isMember) {
      items.add(const BottomNavigationBarItem(
          icon: Icon(Icons.home), label: 'الرئيسية'));
    }
    if (!isMember || _canRead(TeamPermissions.businesses)) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.card_travel),
        label: 'الاعمال',
      ));
    }
    if (!isMember || _canRead(TeamPermissions.workers)) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.groups_2),
        label: 'العمال',
      ));
    }
    if (!isMember || _canRead(TeamPermissions.expenses)) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.attach_money),
        label: 'المصروفات',
      ));
    }
    if (!isMember || _canRead(TeamPermissions.reports)) {
      items.add(const BottomNavigationBarItem(
        icon: Icon(Icons.leaderboard),
        label: 'التقارير',
      ));
    }
    items.add(const BottomNavigationBarItem(
      icon: Icon(Icons.settings),
      label: 'الاعدادات',
    ));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pages = _buildPages();
    final tabs = _buildTabs();

    // ضمان أن التبويب الحالي ما زال داخل النطاق بعد تغيّر الصلاحيات.
    if (selectedIndex >= pages.length) {
      selectedIndex = 0;
    }

    return Scaffold(
      key: homePageKey,
      body: pages[selectedIndex],
      bottomNavigationBar: tabs.length >= 2
          ? BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              unselectedItemColor: colorScheme.onSurfaceVariant,
              selectedItemColor: colorScheme.primary,
              backgroundColor: colorScheme.surface,
              elevation: 8,
              currentIndex: selectedIndex,
              onTap: (index) {
                setState(() {
                  selectedIndex = index;
                });
              },
              showUnselectedLabels: true,
              selectedLabelStyle: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              unselectedLabelStyle: TextStyle(fontSize: 12),
              items: tabs,
            )
          : null,
    );
  }
}