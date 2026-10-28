import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';
import 'package:opennutritracker/core/utils/widget/polar_widget_extras.dart';

/// Fork: the background refresh recomputes the Polar goal for the widgets
/// with the same formula as Home (BMR + Polar active + activities + slider;
/// 2.2 / 0.8 g per kg, carbs the rest).
void main() {
  // 164 cm, 51 years, male: Mifflin-St Jeor without the weight term.
  const bmrRest = 6.25 * 164 - 5 * 51 + 5;
  const base = PolarWidgetBase(
    dayId: '2026-10-28',
    offsetMinutes: 0,
    bmrWithoutWeight: bmrRest,
    activityKcal: 0,
    adjustmentKcal: -300,
    proteinGPerKg: 2.2,
    fatGPerKg: 0.8,
    weightKg: 65.4,
  );

  test('the goal is the one Home showed on the Pixel 10 Pro', () {
    expect(base.bmr(65.4).round(), 1429);
    expect(base.goal(weightKg: 65.4, polarActiveKcal: 0).round(), 1129);
    expect(base.goal(weightKg: 65.4, polarActiveKcal: 483).round(), 1612);
  });

  test('applyTo recomputes goal and macro goals and keeps what was eaten', () {
    final snapshot = {
      'hasData': true,
      'day': '2026-10-28',
      'consumed': 1191,
      'goal': 1129,
      'macros': {
        'carbs': [66, 20],
        'fat': [53, 52],
        'protein': [100, 144],
      },
      'water': [250, 1900],
    };

    final updated = base.applyTo(snapshot, weightKg: 65.4, polarActiveKcal: 483);

    final protein = MacroCalc.getProteinGoalFromBodyWeight(65.4, 2.2);
    final fat = MacroCalc.getFatGoalFromBodyWeight(65.4, 0.8);
    final carbs = MacroCalc.getCarbsGoalBodyWeightBased(
      base.goal(weightKg: 65.4, polarActiveKcal: 483),
      protein,
      fat,
    );
    expect(updated['goal'], 1612);
    expect(updated['consumed'], 1191);
    expect(updated['water'], [250, 1900]);
    expect(updated['macros'], {
      'carbs': [66, carbs.round()],
      'fat': [53, fat.round()],
      'protein': [100, protein.round()],
    });
  });

  test('extras carry the breakdown and the time of the computation', () {
    final extras = base.extras(
      weightKg: 65.4,
      polarActiveKcal: 483,
      at: DateTime(2026, 10, 28, 16, 40),
    );

    expect(extras['status'], 'Polar · Stand 16:40');
    expect(extras['details'], [
      ['Grundumsatz', '1429'],
      ['Polar aktiv', '+483'],
      ['Anpassung', '−300'],
    ]);
  });

  test('the day ends at the configured boundary', () {
    final shifted = PolarWidgetBase.fromJson({
      ...base.toJson(),
      'offsetMinutes': 4 * 60,
    });
    expect(shifted.dayEnd(), DateTime(2026, 10, 29, 4));
    expect(PolarWidgetBase.fromJson(base.toJson()).toJson(), base.toJson());
  });
}
