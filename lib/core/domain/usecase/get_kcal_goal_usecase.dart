import 'package:collection/collection.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/polar_bmr_calc.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';
import 'package:opennutritracker/core/utils/calc/day_boundary_calc.dart';

class GetKcalGoalUsecase {
  final UserRepository _userRepository;
  final ConfigRepository _configRepository;
  final UserActivityRepository _userActivityRepository;
  // Null for goal calculations that must not use the device's Polar data,
  // e.g. seeding a tracked day for another profile (Polar belongs to the
  // device owner, not to every profile).
  final PolarInfluxdbDataSource? _polarDataSource;

  GetKcalGoalUsecase(this._userRepository, this._configRepository, this._userActivityRepository, [this._polarDataSource]);

  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async {
    final user = userEntity ?? await _userRepository.getUserData();
    final config = await _configRepository.getConfig();
    final totalKcalActivities =
        totalKcalActivitiesParam ??
        (await _userActivityRepository.getAllUserActivityByDate(
          // #586: the query takes a day label, so "today" has to be
          // resolved through the boundary first. A raw DateTime.now()
          // here asks for the wall-clock date, which between midnight
          // and the boundary is a different day than the one Home's
          // activity list shows — the goal would silently drop those
          // burned calories.
          DayBoundaryCalc.currentLogicalDayLabel(
            config.dayStartOffsetHours,
            config.dayStartOffsetMinutes,
          ),
          dayStartOffsetHours: config.dayStartOffsetHours,
          dayStartOffsetMinutes: config.dayStartOffsetMinutes,
        )).map((activity) => activity.burnedKcal).toList().sum;

    // When Polar is configured, Polar's measured active energy replaces the
    // PAL estimate: BMR (Mifflin-St Jeor, InfluxDB weight when available)
    // + Polar active kcal + manually logged activities + slider. The slider
    // is signed — negative to lose weight, positive to gain.
    final polar = _polarDataSource;
    if (polar != null && await polar.isPolarConfigured()) {
      final weightKg = await polar.fetchLatestWeightKg() ?? user.weightKG;
      final bmr = PolarBmrCalc.getBMRMifflinStJeor1990(user.copyWith(weightKG: weightKg));
      // The logical day (day boundary), same as the home screen's.
      final day = DayBoundaryCalc.currentLogicalDayMinutes(config.dayStartOffsetTotalMinutes);
      final polarActiveKcal = await polar.fetchActiveKcalForDate(day) ?? 0;
      return bmr + polarActiveKcal + totalKcalActivities + (config.userKcalAdjustment ?? 0);
    }

    return CalorieGoalCalc.getTotalKcalGoal(
      user,
      totalKcalActivities,
      kcalUserAdjustment: config.userKcalAdjustment,
      caloriesTaperEnabled: user.caloriesTaperEnabled,
    );
  }
}
