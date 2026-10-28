import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/core/presentation/widgets/add_item_bottom_sheet.dart';
import 'package:opennutritracker/core/presentation/widgets/demo_mode_banner.dart';
import 'package:opennutritracker/core/styles/app_palette.dart';
import 'package:opennutritracker/core/utils/health_rationale_service.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/core/utils/meal_type_suggester.dart';
import 'package:opennutritracker/core/utils/navigation_options.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_link.dart';
import 'package:opennutritracker/features/diary/diary_page.dart';
import 'package:opennutritracker/core/presentation/widgets/home_appbar.dart';
import 'package:opennutritracker/features/home/home_page.dart';
import 'package:opennutritracker/features/home/presentation/widgets/log_water_dialog.dart';
import 'package:opennutritracker/core/presentation/widgets/main_appbar.dart';
import 'package:opennutritracker/features/profile/profile_page.dart';
import 'package:opennutritracker/features/trends/presentation/trends_page.dart';
import 'package:opennutritracker/generated/l10n.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _selectedPageIndex = 0;
  bool _isDemoData = false;

  /// Guards against two lifecycle events asking the platform at once. The
  /// platform side clears the flag on read, so a race would not open the
  /// screen twice — but it would spend two channel round trips finding out.
  bool _checkingHealthRationale = false;

  late List<Widget> _bodyPages;
  late List<PreferredSizeWidget> _appbarPages;

  StreamSubscription<Uri?>? _widgetLinks;
  static final _followedWidgetLinks = <String>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadConfigDrivenUi();
    _listenToWidgetLinks();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetLinks?.cancel();
    super.dispose();
  }

  /// Taps on the Android home-screen widgets (#832): the one that started
  /// the app, and any while it is running.
  Future<void> _listenToWidgetLinks() async {
    _widgetLinks = HomeWidget.widgetClicked.listen(
      _openWidgetLink,
      onError: (_) {},
    );
    try {
      _openWidgetLink(await HomeWidget.initiallyLaunchedFromHomeWidget());
    } on MissingPluginException {
      // Tests and platforms without the plugin.
    } on PlatformException {
      // No launch intent to read.
    }
  }

  /// Runs after the frame in progress: a cold start reaches this while the
  /// splash route is still being replaced by this one.
  void _openWidgetLink(Uri? uri) {
    final link = CalorieWidgetLink.parse(uri);
    // The same tap can be read twice — as the launching intent and from the
    // stream, or again by a later MainScreen — so each is followed once.
    // MainActivity stamps every tap, which keeps two real taps apart.
    if (link == null || !_followedWidgetLinks.add(uri.toString())) return;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _followWidgetLink(link),
    );
  }

  void _followWidgetLink(CalorieWidgetLink link) {
    if (!mounted) return;
    // Close whatever sits on top of this screen, never this screen itself:
    // during the splash hand-over it is not yet the first route.
    final self = ModalRoute.of(context);
    Navigator.of(context).popUntil((route) => route == self || route.isFirst);
    _setPage(0);
    switch (link) {
      case CalorieWidgetLink.open:
        break;
      case CalorieWidgetLink.addFood:
        _onFabPressed(context);
      case CalorieWidgetLink.addWater:
        showDialog<void>(
          context: context,
          builder: (_) => const LogWaterDialog(),
        );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // The activity is singleTop, so Health Connect reaching a process that is
    // already running never rebuilds this screen — a resume is the only signal
    // that an intent arrived.
    if (state == AppLifecycleState.resumed) {
      _maybeOpenHealthRationale();
    }
  }

  // Checked once per screen instance rather than kept live — leaving demo mode
  // always replaces this whole screen with the onboarding route (see
  // DemoModeBanner), so there is no in-place transition to react to.
  //
  // The policy-change notice #887 specified is deliberately **not** shown for
  // revision 1. #887's reasoning stands on the record and was not refuted —
  // the corrections name recipients that were always receiving data, so users
  // were under-informed for the whole time rather than recently — but the call
  // was made not to spend a first-launch dialog on it. The mechanism itself is
  // kept, not deleted: `URLConst.policyRevision`, the seeding in
  // `OnboardingBloc.saveOnboardingData` and `PolicyChangeDialog` are all still
  // live and tested, so a future revision that does warrant telling people can
  // restore this by calling the dialog again. What is gone is one call, not
  // the ability to notify.
  Future<void> _loadConfigDrivenUi() async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!mounted) return;
    setState(() => _isDemoData = config.isDemoData);
    await _maybeOpenHealthRationale();
  }

  /// Opens the health-sync screen when Health Connect asked the app to explain
  /// what it wants health data for (#927).
  ///
  /// Health Connect starts the app rather than rendering anything itself, so
  /// without this the user is dropped on the diary having asked a question
  /// nothing answered. The screen names the data, says what it is used for,
  /// and links the privacy policy.
  Future<void> _maybeOpenHealthRationale() async {
    if (_checkingHealthRationale) return;
    _checkingHealthRationale = true;
    final bool requested;
    try {
      requested = await HealthRationaleService.consumePendingRequest();
    } finally {
      _checkingHealthRationale = false;
    }
    if (!requested || !mounted) return;
    await Navigator.of(context).pushNamed(NavigationOptions.healthSyncRoute);
  }

  @override
  void didChangeDependencies() {
    _bodyPages = [
      const HomePage(),
      const DiaryPage(),
      const TrendsPage(),
      const ProfilePage(),
    ];
    _appbarPages = [
      const HomeAppbar(),
      MainAppbar(title: S.of(context).diaryLabel, iconData: Icons.book),
      MainAppbar(title: S.of(context).trendsLabel, iconData: Icons.insights),
      MainAppbar(title: S.of(context).youLabel, iconData: Icons.account_circle),
    ];
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = isDark ? AppPalette.dark : AppPalette.light;
    return Scaffold(
      appBar: _appbarPages[_selectedPageIndex],
      body: Column(
        children: [
          if (_isDemoData) const DemoModeBanner(),
          Expanded(
            child: IndexedStack(
              index: _selectedPageIndex,
              children: _bodyPages,
            ),
          ),
        ],
      ),
      floatingActionButton: Semantics(
        identifier: 'fab-add-item',
        child: FloatingActionButton(
          onPressed: () => _onFabPressed(context),
          tooltip: S.of(context).addLabel,
          child: const Icon(Icons.add, size: 30),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 78,
        padding: EdgeInsets.zero,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: Row(
          children: [
            _NavItem(
              id: 'nav-home',
              icon: Icons.home_outlined,
              selectedIcon: Icons.home_rounded,
              label: S.of(context).homeLabel,
              index: 0,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            _NavItem(
              id: 'nav-diary',
              icon: Icons.book_outlined,
              selectedIcon: Icons.book_rounded,
              label: S.of(context).diaryLabel,
              index: 1,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            const SizedBox(width: 64), // notch gap for the centre Add FAB
            _NavItem(
              id: 'nav-trends',
              icon: Icons.insights_outlined,
              selectedIcon: Icons.insights_rounded,
              label: S.of(context).trendsLabel,
              index: 2,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
            _NavItem(
              id: 'nav-you',
              icon: Icons.account_circle_outlined,
              selectedIcon: Icons.account_circle_rounded,
              label: S.of(context).youLabel,
              index: 3,
              selectedIndex: _selectedPageIndex,
              palette: palette,
              onTap: _setPage,
            ),
          ],
        ),
      ),
    );
  }

  void _setPage(int selectedIndex) {
    setState(() {
      _selectedPageIndex = selectedIndex;
    });
  }

  Future<void> _onFabPressed(BuildContext context) async {
    final config = await locator<GetConfigUsecase>().getConfig();
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return AddItemBottomSheet(
          day: DateTime.now(),
          showActivityTracking: config.showActivityTracking,
          usesImperialUnits: config.usesImperialFoodUnits,
          suggestedType: MealTypeSuggester.suggestFromTime(
            DateTime.now(),
            mealSharesPct: config.mealKcalSharesPct,
          ),
        );
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  final String id;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;
  final int selectedIndex;
  final AppPalette palette;
  final void Function(int) onTap;

  const _NavItem({
    required this.id,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = index == selectedIndex;
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : palette.textMuted;
    return Expanded(
      child: Semantics(
        identifier: id,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => onTap(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 26),
                const SizedBox(height: 3),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
