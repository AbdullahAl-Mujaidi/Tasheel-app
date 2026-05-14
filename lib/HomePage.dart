import 'package:flutter/material.dart';
import 'package:fkra/BusinessPage.dart';
import 'package:fkra/ExpensesPage.dart';
import 'package:fkra/ReportsPage.dart';
import 'package:fkra/SettingsPage.dart';
import 'package:fkra/WorkersPage.dart';
import 'package:fkra/home.dart';

class Homepage extends StatefulWidget {
  final String userId;
  const Homepage({super.key, required this.userId});

  @override
  State<Homepage> createState() => _HomepageState();
}

class _HomepageState extends State<Homepage> {
  static final GlobalKey<_HomepageState> homePageKey = GlobalKey();

  int selectedIndex = 0;

  void changePage(int index) {
    setState(() {
      selectedIndex = index;
    });
  }

  late final List<Widget> _pages = [
    HomePage(changePage: changePage, userId: widget.userId),
    BusinessPage(userId: widget.userId),
    WorkersPage(userId: widget.userId),
    ExpensesPage(userId: widget.userId),
    ReportsPage(userId: widget.userId),
    SettingsPage(userId: widget.userId),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      key: homePageKey,
      body: _pages[selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
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
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'الرئيسية'),
          BottomNavigationBarItem(
            icon: Icon(Icons.card_travel),
            label: 'الاعمال',
          ),
          BottomNavigationBarItem(icon: Icon(Icons.groups_2), label: 'العمال'),
          BottomNavigationBarItem(
            icon: Icon(Icons.attach_money),
            label: 'المصروفات',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'التقارير',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'الاعدادات',
          ),
        ],
      ),
    );
  }
}
