import 'dart:convert';

import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_labels.dart';

/// Today's figures for the home-screen widgets: the iOS calorie widget and
/// the Android widgets (#832).
///
/// The widgets cannot open the encrypted Hive database, so the app writes
/// this snapshot into the shared App Group (iOS) or the plugin's shared
/// preferences (Android) whenever Home finishes loading. Kilocalories and
/// grams are the stored units. The in-app kilojoule display preference is
/// not applied here.
class CalorieWidgetSnapshot {
  static const appGroupId = 'group.com.opennutritracker.ont.opennutritracker';
  static const developAppGroupId =
      'group.com.opennutritracker.ont.opennutritracker.develop';
  static const iosWidgetKind = 'CalorieProgressWidget';

  /// The Android widget providers, one per size (#832). Their package is
  /// the Kotlin namespace, which both flavours share.
  static const androidProviders = [
    'com.opennutritracker.ont.opennutritracker.widget.CalorieWidgetSmallProvider',
    'com.opennutritracker.ont.opennutritracker.widget.CalorieWidgetMediumProvider',
    'com.opennutritracker.ont.opennutritracker.widget.CalorieWidgetStripProvider',
    'com.opennutritracker.ont.opennutritracker.widget.CalorieWidgetLargeProvider',
  ];

  /// The App Group key the snapshot lives under: the figures and the
  /// labels that describe them, as one JSON string. One key is one platform
  /// write, so the extension reads either the old snapshot or the new one,
  /// never a mix of the two.
  static const storageKey = 'ont_calorie_snapshot';

  final bool hasData;
  final String dayId;
  final int offsetMinutes;
  final int consumedKcal;
  final int goalKcal;

  /// Today's macros, eaten and goal, in grams. Read by the Android widgets;
  /// the iOS widget shows calories only.
  final CalorieWidgetMacros macros;

  /// Kilocalories burned by logged activities today.
  final int burnedKcal;

  final int waterMl;
  final int waterGoalMl;

  /// Kilocalories eaten per meal, in Home's order.
  final CalorieWidgetMeals meals;

  const CalorieWidgetSnapshot({
    required this.hasData,
    required this.dayId,
    required this.offsetMinutes,
    required this.consumedKcal,
    required this.goalKcal,
    this.macros = CalorieWidgetMacros.none,
    this.burnedKcal = 0,
    this.waterMl = 0,
    this.waterGoalMl = 0,
    this.meals = CalorieWidgetMeals.none,
  });

  /// Builds the snapshot Home should publish.
  ///
  /// [consumedKcal] is today's supplied intake and [goalKcal] is the
  /// daily goal, both already computed by Home. A goal of zero, or a
  /// negative goal, means there is no profile figure to show.
  ///
  /// [logicalDay] is the day the figures were read for. Home passes the
  /// one its load started on, so a load that crosses the day boundary does
  /// not stamp the old day's figures with the new day. Without it, the
  /// logical day of [now] is used.
  factory CalorieWidgetSnapshot.fromHome({
    required double consumedKcal,
    required double goalKcal,
    required int offsetMinutes,
    CalorieWidgetMacros macros = CalorieWidgetMacros.none,
    double burnedKcal = 0,
    int waterMl = 0,
    int waterGoalMl = 0,
    CalorieWidgetMeals meals = CalorieWidgetMeals.none,
    DateTime? logicalDay,
    DateTime? now,
  }) {
    final offset = sanitiseOffsetMinutes(offsetMinutes);
    final day =
        logicalDay ??
        DayBoundaryCalc.logicalDayOfMinutes(now ?? DateTime.now(), offset);
    final goal = goalKcal.round();
    final hasData = goal > 0;
    return CalorieWidgetSnapshot(
      hasData: hasData,
      dayId: formatDayId(day),
      offsetMinutes: offset,
      consumedKcal: hasData ? consumedKcal.round() : 0,
      goalKcal: hasData ? goal : 0,
      macros: hasData ? macros : CalorieWidgetMacros.none,
      burnedKcal: hasData ? burnedKcal.round() : 0,
      waterMl: hasData ? waterMl : 0,
      waterGoalMl: hasData ? waterGoalMl : 0,
      meals: hasData ? meals : CalorieWidgetMeals.none,
    );
  }

  /// True when this snapshot still belongs to the logical day of [moment].
  bool isCurrentAt(DateTime moment) {
    if (!hasData || dayId.isEmpty) return false;
    final logicalDay = DayBoundaryCalc.logicalDayOfMinutes(
      moment,
      offsetMinutes,
    );
    return dayId == formatDayId(logicalDay);
  }

  /// Wall-clock instant when this logical day ends and the widget should
  /// drop yesterday's numbers.
  DateTime nextBoundary() {
    final parts = dayId.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    final start = DateTime(year, month, day);
    return start.add(Duration(days: 1, minutes: offsetMinutes));
  }

  Map<String, Object> toJson() => {
    'hasData': hasData,
    'day': dayId,
    'offsetMinutes': offsetMinutes,
    'consumed': consumedKcal,
    'goal': goalKcal,
    'macros': macros.toJson(),
    'burned': burnedKcal,
    'water': [waterMl, waterGoalMl],
    'meals': meals.toJson(),
  };

  /// The value stored under [storageKey]: this snapshot with the figure
  /// labels in [labels].
  String encode(CalorieWidgetLabels labels) =>
      jsonEncode({...toJson(), 'labels': labels.figureJson()});

  /// The App Group for the build with [bundleId]. The develop flavour has
  /// its own bundle id and its own group, so a develop install next to the
  /// App Store build can never overwrite or clear that build's widget. It
  /// must agree with `ONT_APP_GROUP_ID` in the Xcode project.
  static String appGroupIdFor(String bundleId) =>
      bundleId.endsWith('.develop') ? developAppGroupId : appGroupId;

  static int sanitiseOffsetMinutes(int offsetMinutes) {
    if (offsetMinutes < 0 || offsetMinutes >= 24 * 60) return 0;
    return offsetMinutes;
  }

  static String formatDayId(DateTime day) {
    final year = day.year.toString().padLeft(4, '0');
    final month = day.month.toString().padLeft(2, '0');
    final dayOfMonth = day.day.toString().padLeft(2, '0');
    return '$year-$month-$dayOfMonth';
  }
}

/// Today's carbs, fat and protein, eaten and goal, rounded to whole grams.
class CalorieWidgetMacros {
  final int carbsG;
  final int carbsGoalG;
  final int fatG;
  final int fatGoalG;
  final int proteinG;
  final int proteinGoalG;

  const CalorieWidgetMacros({
    required this.carbsG,
    required this.carbsGoalG,
    required this.fatG,
    required this.fatGoalG,
    required this.proteinG,
    required this.proteinGoalG,
  });

  static const none = CalorieWidgetMacros(
    carbsG: 0,
    carbsGoalG: 0,
    fatG: 0,
    fatGoalG: 0,
    proteinG: 0,
    proteinGoalG: 0,
  );

  /// From Home's unrounded totals and goals.
  factory CalorieWidgetMacros.fromHome({
    required double carbs,
    required double carbsGoal,
    required double fat,
    required double fatGoal,
    required double protein,
    required double proteinGoal,
  }) => CalorieWidgetMacros(
    carbsG: carbs.round(),
    carbsGoalG: carbsGoal.round(),
    fatG: fat.round(),
    fatGoalG: fatGoal.round(),
    proteinG: protein.round(),
    proteinGoalG: proteinGoal.round(),
  );

  /// Each macro as `[eaten, goal]`.
  Map<String, List<int>> toJson() => {
    'carbs': [carbsG, carbsGoalG],
    'fat': [fatG, fatGoalG],
    'protein': [proteinG, proteinGoalG],
  };
}

/// Kilocalories eaten per meal today, rounded.
class CalorieWidgetMeals {
  final int breakfastKcal;
  final int lunchKcal;
  final int dinnerKcal;
  final int snackKcal;

  const CalorieWidgetMeals({
    required this.breakfastKcal,
    required this.lunchKcal,
    required this.dinnerKcal,
    required this.snackKcal,
  });

  static const none = CalorieWidgetMeals(
    breakfastKcal: 0,
    lunchKcal: 0,
    dinnerKcal: 0,
    snackKcal: 0,
  );

  Map<String, int> toJson() => {
    'breakfast': breakfastKcal,
    'lunch': lunchKcal,
    'dinner': dinnerKcal,
    'snack': snackKcal,
  };
}
