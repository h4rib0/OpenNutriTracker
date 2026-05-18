import 'package:collection/collection.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/bmr_calc.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';

class GetKcalGoalUsecase {
  final UserRepository _userRepository;
  final ConfigRepository _configRepository;
  final UserActivityRepository _userActivityRepository;
  final PolarInfluxdbDataSource _polarDataSource;

  GetKcalGoalUsecase(
    this._userRepository,
    this._configRepository,
    this._userActivityRepository,
    this._polarDataSource,
  );

  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
  }) async {
    final user = userEntity ?? await _userRepository.getUserData();
    final config = await _configRepository.getConfig();
    final totalKcalActivities = totalKcalActivitiesParam ??
        (await _userActivityRepository.getAllUserActivityByDate(
          DateTime.now(),
        ))
            .map((activity) => activity.burnedKcal)
            .toList()
            .sum;

    // When Polar is configured: BMR + Polar-kcal + manual activity kcal + slider adjustment.
    // No PAL factor, no weight-goal adjustment — Polar tracks actual burn directly.
    if (await _polarDataSource.isPolarConfigured()) {
      final bmr = BMRCalc.getBMRMifflinStJeor1990(user);
      final polarKcal =
          await _polarDataSource.fetchActiveKcalForDate(DateTime.now()) ?? 0;
      return bmr + polarKcal + totalKcalActivities + (config.userKcalAdjustment ?? 0);
    }

    return CalorieGoalCalc.getTotalKcalGoal(
      user,
      totalKcalActivities,
      kcalUserAdjustment: config.userKcalAdjustment,
      caloriesTaperEnabled: user.caloriesTaperEnabled,
    );
  }
}
