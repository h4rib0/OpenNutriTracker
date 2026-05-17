import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_weight_goal_entity.dart';
import 'package:opennutritracker/core/utils/calc/tdee_calc.dart';

class CalorieGoalCalc {
  static const double loseWeightKcalAdjustment = -500;
  static const double maintainWeightKcalAdjustment = 0;
  static const double gainWeightKcalAdjustment = 500;

  static double getDailyKcalLeft(
    double totalKcalGoal,
    double totalKcalIntake,
  ) =>
      totalKcalGoal - totalKcalIntake;

  static double getTdee(UserEntity userEntity) =>
      TDEECalc.getTDEEKcalMifflinStJeor(userEntity);

  // 1 kg of body fat ≈ 7700 kcal; spread over 7 days → ~1100 kcal/day per kg/week
  static const double _kcalPerKgPerWeekDaily = 1100.0;

  static double getTotalKcalGoal(
    UserEntity userEntity,
    double totalKcalActivities, {
    double? kcalUserAdjustment,
  }) =>
      getTdee(userEntity) +
      getKcalGoalAdjustment(userEntity.goal,
          weeklyWeightGoalKg: userEntity.weeklyWeightGoalKg) +
      (kcalUserAdjustment ?? 0) +
      totalKcalActivities;

  static double getKcalGoalAdjustment(UserWeightGoalEntity goal,
      {double? weeklyWeightGoalKg}) {
    if (weeklyWeightGoalKg != null) {
      return weeklyWeightGoalKg * _kcalPerKgPerWeekDaily;
    }
    double kcalAdjustment;
    if (goal == UserWeightGoalEntity.loseWeight) {
      kcalAdjustment = loseWeightKcalAdjustment;
    } else if (goal == UserWeightGoalEntity.gainWeight) {
      kcalAdjustment = gainWeightKcalAdjustment;
    } else {
      kcalAdjustment = maintainWeightKcalAdjustment;
    }
    return kcalAdjustment;
  }
}
