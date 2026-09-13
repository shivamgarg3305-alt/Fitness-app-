import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../screens/dashboard_screen.dart';
import '../screens/sleep_analysis_screen.dart';
import '../screens/strain_screen.dart';
import '../screens/recovery_screen.dart';
import '../screens/stress_monitor_screen.dart';
import '../screens/journal_impact_screen.dart';
import '../screens/menstrual_insights_screen.dart';
import '../screens/healthspan_screen.dart';
import '../screens/active_tracking_screen.dart';
import '../screens/user_profile_screen.dart';

/// Root navigation shell.
///
/// 8+ destinations don't fit a bottom nav well (5 is the practical max
/// before it gets cramped/unreadable), so this uses the common pattern of
/// 4 primary tabs — Dashboard, Sleep, Strain, Recovery — plus a "More"
/// tab that opens a menu for the secondary screens (Stress, Journal,
/// Menstrual Insights, Healthspan). Active Tracking is reached via the
/// dashboard's "start sleep" entry point, not a tab, since it's a modal
/// full-screen flow rather than a place you browse to.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _primaryScreens = [
    DashboardScreen(),
    SleepAnalysisScreen(),
    StrainScreen(),
    RecoveryScreen(),
  ];

  void _onTabTap(int i) {
    if (i == 4) {
      _showMoreMenu();
      return;
    }
    setState(() => _index = i);
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navyBase,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              _MoreMenuItem(
                icon: Icons.show_chart_rounded,
                label: 'Stress Monitor',
                onTap: () => _pushSecondary(const StressMonitorScreen()),
              ),
              _MoreMenuItem(
                icon: Icons.menu_book_rounded,
                label: 'Journal Impact',
                onTap: () => _pushSecondary(const JournalImpactScreen()),
              ),
              _MoreMenuItem(
                icon: Icons.calendar_month_rounded,
                label: 'Menstrual Insights',
                onTap: () => _pushSecondary(const MenstrualInsightsScreen()),
              ),
              _MoreMenuItem(
                icon: Icons.favorite_border_rounded,
                label: 'Healthspan',
                onTap: () => _pushSecondary(const HealthspanScreen()),
              ),
              _MoreMenuItem(
                icon: Icons.person_outline_rounded,
                label: 'Your Profile',
                onTap: () => _pushSecondary(const UserProfileScreen()),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _pushSecondary(Widget screen) {
    Navigator.of(context).pop(); // close the sheet
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _primaryScreens),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.cyan,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActiveTrackingScreen()),
        ),
        child: const Icon(Icons.bedtime_rounded, color: AppColors.navyDeep),
      ),
      bottomNavigationBar: _BottomBar(currentIndex: _index, onTap: _onTabTap),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.currentIndex, required this.onTap});

  static const _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.bedtime_rounded, label: 'Sleep'),
    (icon: Icons.bolt_rounded, label: 'Strain'),
    (icon: Icons.favorite_rounded, label: 'Recovery'),
    (icon: Icons.grid_view_rounded, label: 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navyBase,
      child: SafeArea(
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (int i = 0; i < _tabs.length; i++)
                _TabIcon(
                  icon: _tabs[i].icon,
                  label: _tabs[i].label,
                  selected: i != 4 && currentIndex == i,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
class _TabIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabIcon({required this.icon, required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.cyan : AppColors.textDim;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: color, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _MoreMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _MoreMenuItem({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: AppColors.cyan),
      title: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
    );
  }
}
