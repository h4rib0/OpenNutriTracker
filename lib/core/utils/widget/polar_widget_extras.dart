import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_snapshot.dart';

/// Fork-only: the Polar parts of the Android home-screen widgets.
///
/// With Polar the goal grows during the day with the active energy Polar
/// measures, but Home only writes the widget snapshot when the app runs. So
/// Home also stores what the goal is made of ([PolarWidgetBase]), and a
/// background callback, started by the widget's periodic redraw, fetches the
/// weight and active energy from InfluxDB and recomputes the goal and macro
/// goals with the same formula as `GetKcalGoalUsecase` / `GetMacroGoalUsecase`.
/// What was eaten only changes in the app, so the snapshot's eaten figures
/// stay as Home wrote them.
abstract final class PolarWidgetExtras {
  /// `{"status": "...", "details": [["label", "value"], ...]}`, read by the
  /// large widget (CalorieWidget.kt).
  static const extrasKey = 'ont_calorie_extras';
  static const baseKey = 'ont_polar_widget_base';

  /// Millis of the last goal computation, app or background. The widget
  /// starts a background refresh only when this is older than [refreshEvery].
  static const refreshedAtKey = 'ont_polar_refreshed_at';
  static const refreshEvery = Duration(minutes: 15);

  static final _log = Logger('PolarWidgetExtras');

  /// Called by Home after it published the snapshot. Without Polar the
  /// extras are removed, so the widget falls back to the upstream rows.
  static Future<void> publish({
    required PolarWidgetBase? base,
    required double weightKg,
    required double polarActiveKcal,
    required DateTime now,
  }) async {
    try {
      if (base == null) {
        await _save({extrasKey: null, baseKey: null, refreshedAtKey: null});
        await _redraw();
        return;
      }
      await _save({
        baseKey: jsonEncode(base.toJson()),
        extrasKey: jsonEncode(
          base.extras(
            weightKg: weightKg,
            polarActiveKcal: polarActiveKcal,
            at: now,
          ),
        ),
        refreshedAtKey: now.millisecondsSinceEpoch.toString(),
      });
      await _scheduleRefreshes(base, now);
      await _redraw();
    } on MissingPluginException {
      // Tests and platforms without the plugin.
    } catch (e) {
      _log.warning('Could not publish the Polar widget extras: $e');
    }
  }

  /// Background: InfluxDB → new goal and macro goals → widget.
  static Future<void> refresh({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final rawBase = await HomeWidget.getWidgetData<String>(baseKey);
    final rawSnapshot = await HomeWidget.getWidgetData<String>(
      CalorieWidgetSnapshot.storageKey,
    );
    if (rawBase == null || rawSnapshot == null) return;
    var base = PolarWidgetBase.fromJson(
      jsonDecode(rawBase) as Map<String, dynamic>,
    );
    var snapshot = jsonDecode(rawSnapshot) as Map<String, dynamic>;
    final day = DayBoundaryCalc.logicalDayOfMinutes(at, base.offsetMinutes);
    final dayId = CalorieWidgetSnapshot.formatDayId(day);

    final polar = PolarInfluxdbDataSource();
    if (!await polar.isPolarConfigured()) return;

    // A day the app has not been opened on yet: nothing is eaten, logged
    // or drunk until it is, so the background can start it on Polar's
    // figures instead of showing "Open the app" until then.
    final newDay = base.dayId != dayId;
    if (newDay) {
      base = base.forDay(dayId);
      snapshot = PolarWidgetBase.emptyDay(snapshot, dayId);
    }

    final weightKg = await polar.fetchLatestWeightKg() ?? base.weightKg;
    final activeKcal = await polar.fetchActiveKcalForDate(day) ?? 0;
    final updated = base.applyTo(
      snapshot,
      weightKg: weightKg,
      polarActiveKcal: activeKcal,
    );
    await _save({
      CalorieWidgetSnapshot.storageKey: jsonEncode(updated),
      if (newDay) baseKey: jsonEncode(base.toJson()),
      extrasKey: jsonEncode(
        base.extras(weightKg: weightKg, polarActiveKcal: activeKcal, at: at),
      ),
      refreshedAtKey: at.millisecondsSinceEpoch.toString(),
    });
    if (newDay) await _scheduleRefreshes(base, at);
    await _redraw();
  }

  /// One redraw every [refreshEvery] until the day ends, plus the boundary
  /// itself. Replaces the boundary-only schedule the upstream writer sets.
  static Future<void> _scheduleRefreshes(
    PolarWidgetBase base,
    DateTime now,
  ) async {
    final boundary = base.dayEnd();
    final times = <DateTime>[];
    for (
      var t = now.add(refreshEvery);
      t.isBefore(boundary);
      t = t.add(refreshEvery)
    ) {
      times.add(t);
    }
    times.add(boundary);
    for (final provider in CalorieWidgetSnapshot.androidProviders) {
      try {
        await HomeWidget.scheduleWidgetUpdates(
          times,
          qualifiedAndroidName: provider,
        );
      } on PlatformException {
        // A provider missing from this build is skipped.
      }
    }
  }

  static Future<void> _save(Map<String, String?> values) async {
    for (final entry in values.entries) {
      await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
    }
  }

  static Future<void> _redraw() async {
    for (final provider in CalorieWidgetSnapshot.androidProviders) {
      try {
        await HomeWidget.updateWidget(qualifiedAndroidName: provider);
      } on PlatformException {
        // A provider missing from this build is skipped.
      }
    }
  }
}

/// What today's Polar goal is made of, apart from what InfluxDB supplies.
@immutable
class PolarWidgetBase {
  final String dayId;
  final int offsetMinutes;

  /// Mifflin-St Jeor without its weight term (`10 × kg`), which is linear in
  /// the weight for every gender, so the background only adds `10 × kg`.
  final double bmrWithoutWeight;
  final double activityKcal;
  final double adjustmentKcal;
  final double proteinGPerKg;
  final double fatGPerKg;

  /// The weight Home used, for when InfluxDB cannot be reached.
  final double weightKg;

  const PolarWidgetBase({
    required this.dayId,
    required this.offsetMinutes,
    required this.bmrWithoutWeight,
    required this.activityKcal,
    required this.adjustmentKcal,
    required this.proteinGPerKg,
    required this.fatGPerKg,
    required this.weightKg,
  });

  double bmr(double weightKg) => bmrWithoutWeight + 10 * weightKg;

  /// The same person and settings on [dayId], before anything is logged:
  /// no activities yet.
  PolarWidgetBase forDay(String dayId) => PolarWidgetBase(
    dayId: dayId,
    offsetMinutes: offsetMinutes,
    bmrWithoutWeight: bmrWithoutWeight,
    activityKcal: 0,
    adjustmentKcal: adjustmentKcal,
    proteinGPerKg: proteinGPerKg,
    fatGPerKg: fatGPerKg,
    weightKg: weightKg,
  );

  /// [snapshot] turned into [dayId] with nothing eaten, burned or drunk;
  /// the water goal carries over. The goals are filled in by [applyTo].
  static Map<String, dynamic> emptyDay(
    Map<String, dynamic> snapshot,
    String dayId,
  ) {
    final water = snapshot['water'] as List? ?? const [0, 0];
    return {
      ...snapshot,
      'hasData': true,
      'day': dayId,
      'consumed': 0,
      'burned': 0,
      'macros': {
        'carbs': [0, 0],
        'fat': [0, 0],
        'protein': [0, 0],
      },
      'water': [0, water.length > 1 ? water[1] : 0],
      'meals': {'breakfast': 0, 'lunch': 0, 'dinner': 0, 'snack': 0},
    };
  }

  /// Same sum as `GetKcalGoalUsecase` with Polar.
  double goal({required double weightKg, required double polarActiveKcal}) =>
      bmr(weightKg) + polarActiveKcal + activityKcal + adjustmentKcal;

  /// [snapshot] with the goal and the macro goals recomputed; what was
  /// eaten is kept.
  Map<String, dynamic> applyTo(
    Map<String, dynamic> snapshot, {
    required double weightKg,
    required double polarActiveKcal,
  }) {
    final kcal = goal(weightKg: weightKg, polarActiveKcal: polarActiveKcal);
    final protein = MacroCalc.getProteinGoalFromBodyWeight(
      weightKg,
      proteinGPerKg,
    );
    final fat = MacroCalc.getFatGoalFromBodyWeight(weightKg, fatGPerKg);
    final carbs = MacroCalc.getCarbsGoalBodyWeightBased(kcal, protein, fat);
    final macros = Map<String, dynamic>.from(
      snapshot['macros'] as Map? ?? const {},
    );
    List<int> withGoal(String key, double goal) {
      final pair = macros[key] as List? ?? const [0, 0];
      return [(pair.isEmpty ? 0 : pair[0] as int), goal.toInt()];
    }

    return {
      ...snapshot,
      'goal': kcal.round(),
      'macros': {
        'carbs': withGoal('carbs', carbs),
        'fat': withGoal('fat', fat),
        'protein': withGoal('protein', protein),
      },
    };
  }

  /// The large widget's rows and its status line.
  Map<String, Object> extras({
    required double weightKg,
    required double polarActiveKcal,
    required DateTime at,
  }) {
    String signed(double v) => v < 0 ? '−${(-v).round()}' : '+${v.round()}';
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return {
      'status': 'Polar · Stand $time',
      'details': [
        ['Grundumsatz', '${bmr(weightKg).round()}'],
        ['Polar aktiv', signed(polarActiveKcal)],
        if (activityKcal > 0) ['Aktivitäten', signed(activityKcal)],
        ['Anpassung', signed(adjustmentKcal)],
      ].take(3).toList(),
    };
  }

  DateTime dayEnd() {
    final parts = dayId.split('-').map(int.parse).toList();
    return DateTime(
      parts[0],
      parts[1],
      parts[2],
    ).add(Duration(days: 1, minutes: offsetMinutes));
  }

  Map<String, Object> toJson() => {
    'day': dayId,
    'offsetMinutes': offsetMinutes,
    'bmrWithoutWeight': bmrWithoutWeight,
    'activityKcal': activityKcal,
    'adjustmentKcal': adjustmentKcal,
    'proteinGPerKg': proteinGPerKg,
    'fatGPerKg': fatGPerKg,
    'weightKg': weightKg,
  };

  factory PolarWidgetBase.fromJson(Map<String, dynamic> json) =>
      PolarWidgetBase(
        dayId: json['day'] as String,
        offsetMinutes: (json['offsetMinutes'] as num).toInt(),
        bmrWithoutWeight: (json['bmrWithoutWeight'] as num).toDouble(),
        activityKcal: (json['activityKcal'] as num).toDouble(),
        adjustmentKcal: (json['adjustmentKcal'] as num).toDouble(),
        proteinGPerKg: (json['proteinGPerKg'] as num).toDouble(),
        fatGPerKg: (json['fatGPerKg'] as num).toDouble(),
        weightKg: (json['weightKg'] as num).toDouble(),
      );
}

/// Started by the widget's periodic redraw (CalorieWidget.kt) through the
/// plugin's background worker, in an engine of its own.
@pragma('vm:entry-point')
Future<void> polarWidgetBackgroundCallback(Uri? uri) async {
  if (uri?.host != 'widget' || uri?.pathSegments.firstOrNull != 'refresh') {
    return;
  }
  await PolarWidgetExtras.refresh();
}
