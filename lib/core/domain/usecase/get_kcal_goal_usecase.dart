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
  // Null for goal calculations that must not use the device's Polar data,
  // e.g. seeding a tracked day for another profile (Polar belongs to the
  // device owner, not to every profile).
  final PolarInfluxdbDataSource? _polarDataSource;

  GetKcalGoalUsecase(this._userRepository, this._configRepository, this._userActivityRepository, [this._polarDataSource]);

  /// [day] is the logical day whose Polar energy is used (defaults to now).
  Future<double> getKcalGoal({
    UserEntity? userEntity,
    double? totalKcalActivitiesParam,
    double? kcalUserAdjustment,
    DateTime? day,
  }) async {
    final user = userEntity ?? await _userRepository.getUserData();
    final config = await _configRepository.getConfig();
    final totalKcalActivities = totalKcalActivitiesParam ?? (await _userActivityRepository.getAllUserActivityByDate(DateTime.now())).map((activity) => activity.burnedKcal).toList().sum;

    // When Polar is configured, Polar's measured active energy replaces the
    // PAL estimate: BMR (Mifflin-St Jeor, InfluxDB weight when available)
    // + Polar active kcal + manually logged activities + slider. The slider
    // is signed — negative to lose weight, positive to gain.
    final polar = _polarDataSource;
    if (polar != null && await polar.isPolarConfigured()) {
      final weightKg = await polar.fetchLatestWeightKg() ?? user.weightKG;
      final bmr = BMRCalc.getBMRMifflinStJeor1990(user.copyWith(weightKG: weightKg));
      final polarActiveKcal = await polar.fetchActiveKcalForDate(day ?? DateTime.now()) ?? 0;
      return bmr + polarActiveKcal + totalKcalActivities + (config.userKcalAdjustment ?? 0);
    }

    return CalorieGoalCalc.getTotalKcalGoal(user, totalKcalActivities, kcalUserAdjustment: config.userKcalAdjustment, caloriesTaperEnabled: user.caloriesTaperEnabled);
  }
}
