import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_snapshot.dart';

void main() {
  group('CalorieWidgetSnapshot.fromHome', () {
    test('maps supplied intake and goal to rounded kilocalories', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 180.4,
        goalKcal: 2000.6,
        offsetMinutes: 0,
        now: DateTime(2026, 9, 23, 13, 0),
      );

      expect(snapshot.hasData, isTrue);
      expect(snapshot.consumedKcal, 180);
      expect(snapshot.goalKcal, 2001);
      expect(snapshot.dayId, '2026-09-23');
      expect(snapshot.toJson(), {
        'hasData': true,
        'day': '2026-09-23',
        'offsetMinutes': 0,
        'consumed': 180,
        'goal': 2001,
        'macros': {
          'carbs': [0, 0],
          'fat': [0, 0],
          'protein': [0, 0],
        },
        'burned': 0,
        'water': [0, 0],
        'meals': {'breakfast': 0, 'lunch': 0, 'dinner': 0, 'snack': 0},
      });
    });

    test('carries macros, burned energy, water and meals for Android', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 1191.4,
        goalKcal: 1129,
        offsetMinutes: 0,
        macros: CalorieWidgetMacros.fromHome(
          carbs: 66.4,
          carbsGoal: 19.6,
          fat: 53,
          fatGoal: 52.3,
          protein: 100.2,
          proteinGoal: 143.9,
        ),
        burnedKcal: 210.6,
        waterMl: 750,
        waterGoalMl: 1900,
        meals: const CalorieWidgetMeals(
          breakfastKcal: 354,
          lunchKcal: 837,
          dinnerKcal: 0,
          snackKcal: 0,
        ),
        now: DateTime(2026, 10, 28, 16, 40),
      );

      final json = snapshot.toJson();
      // Cut like Home's macro tiles, not rounded: 143.9 g reads 143 there.
      expect(json['macros'], {
        'carbs': [66, 19],
        'fat': [53, 52],
        'protein': [100, 143],
      });
      expect(json['burned'], 211);
      expect(json['water'], [750, 1900]);
      expect(json['meals'], {
        'breakfast': 354,
        'lunch': 837,
        'dinner': 0,
        'snack': 0,
      });
    });

    test('a placeholder carries no macros, water or meals', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 40,
        goalKcal: 0,
        offsetMinutes: 0,
        macros: const CalorieWidgetMacros(
          carbsG: 10,
          carbsGoalG: 200,
          fatG: 2,
          fatGoalG: 60,
          proteinG: 5,
          proteinGoalG: 90,
        ),
        waterMl: 500,
        waterGoalMl: 2000,
        now: DateTime(2026, 10, 28, 8, 0),
      );

      expect(snapshot.toJson()['macros'], CalorieWidgetMacros.none.toJson());
      expect(snapshot.toJson()['water'], [0, 0]);
    });

    test('a zero goal is a placeholder, not a progress ring', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 40,
        goalKcal: 0,
        offsetMinutes: 0,
        now: DateTime(2026, 9, 23, 8, 0),
      );

      expect(snapshot.hasData, isFalse);
      expect(snapshot.toJson()['hasData'], isFalse);
      expect(snapshot.toJson()['consumed'], 0);
    });

    test('an out-of-range offset is treated as midnight', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 10,
        goalKcal: 2000,
        offsetMinutes: 24 * 60,
        now: DateTime(2026, 9, 23, 1, 0),
      );

      expect(snapshot.offsetMinutes, 0);
      expect(snapshot.dayId, '2026-09-23');
    });
  });

  group('CalorieWidgetSnapshot logical day', () {
    test('a 04:00 boundary files 01:00 under the previous day', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 100,
        goalKcal: 2000,
        offsetMinutes: 4 * 60,
        now: DateTime(2026, 9, 23, 1, 0),
      );

      expect(snapshot.dayId, '2026-09-22');
      expect(snapshot.isCurrentAt(DateTime(2026, 9, 23, 2, 0)), isTrue);
      expect(snapshot.isCurrentAt(DateTime(2026, 9, 23, 5, 0)), isFalse);
    });

    test('the next boundary is the following day at the offset', () {
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 100,
        goalKcal: 2000,
        offsetMinutes: 4 * 60,
        now: DateTime(2026, 9, 23, 1, 0),
      );

      expect(snapshot.nextBoundary(), DateTime(2026, 9, 23, 4, 0));
    });

    test('isCurrentAt follows DayBoundaryCalc for the stored offset', () {
      final now = DateTime(2026, 9, 23, 18, 30);
      final snapshot = CalorieWidgetSnapshot.fromHome(
        consumedKcal: 500,
        goalKcal: 2200,
        offsetMinutes: 0,
        now: now,
      );
      final logical = DayBoundaryCalc.logicalDayOfMinutes(now, 0);

      expect(snapshot.dayId, CalorieWidgetSnapshot.formatDayId(logical));
      expect(snapshot.isCurrentAt(now), isTrue);
      expect(snapshot.isCurrentAt(DateTime(2026, 9, 24, 0, 5)), isFalse);
    });
  });
}
