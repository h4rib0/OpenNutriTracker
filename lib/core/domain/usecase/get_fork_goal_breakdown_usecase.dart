import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/utils/calc/polar_bmr_calc.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';

/// Fork-only parts of the calorie-goal transparency screen. Upstream's
/// [KcalGoalBreakdownEntity] explains the IOM path; this explains what the
/// fork does instead, using the same formulas as [GetKcalGoalUsecase] and
/// [GetMacroGoalUsecase] so the totals match the home screen.
class ForkGoalBreakdown {
  /// Set while Polar is configured: the kcal goal is BMR + Polar active
  /// energy + logged activities + slider.
  final PolarKcalBreakdown? polar;

  /// Set while the body-weight macros are in effect (always with Polar,
  /// otherwise opt-in).
  final BodyWeightMacroBreakdown? bodyWeightMacros;

  const ForkGoalBreakdown({this.polar, this.bodyWeightMacros});

  static const none = ForkGoalBreakdown();
}

class PolarKcalBreakdown {
  final double weightKg;
  final bool weightFromInflux;
  final double bmrKcal;
  final double polarActiveKcal;
  final double activityKcal;
  final double manualKcalAdjustment;

  const PolarKcalBreakdown({
    required this.weightKg,
    required this.weightFromInflux,
    required this.bmrKcal,
    required this.polarActiveKcal,
    required this.activityKcal,
    required this.manualKcalAdjustment,
  });

  double get totalKcalGoal =>
      bmrKcal + polarActiveKcal + activityKcal + manualKcalAdjustment;
}

class BodyWeightMacroBreakdown {
  final double totalKcalGoal;
  final double weightKg;
  final double proteinGPerKg;
  final double fatGPerKg;
  final double proteinsGrams;
  final double fatsGrams;
  final double carbsGrams;

  const BodyWeightMacroBreakdown({
    required this.totalKcalGoal,
    required this.weightKg,
    required this.proteinGPerKg,
    required this.fatGPerKg,
    required this.proteinsGrams,
    required this.fatsGrams,
    required this.carbsGrams,
  });
}

class GetForkGoalBreakdownUsecase {
  final UserRepository _userRepository;
  final ConfigRepository _configRepository;
  final PolarInfluxdbDataSource _polarDataSource;

  GetForkGoalBreakdownUsecase(
    this._userRepository,
    this._configRepository,
    this._polarDataSource,
  );

  /// [upstream] supplies the logged-activity kcal (same logical day as the
  /// goal) and the non-Polar total for the body-weight macros.
  Future<ForkGoalBreakdown> getBreakdown(
    KcalGoalBreakdownEntity upstream,
  ) async {
    final config = await _configRepository.getConfig();
    final isPolarActive = await _polarDataSource.isPolarConfigured();
    if (!isPolarActive && !config.useBodyWeightMacros) {
      return ForkGoalBreakdown.none;
    }

    final user = await _userRepository.getUserData();
    final influxWeightKg = isPolarActive
        ? await _polarDataSource.fetchLatestWeightKg()
        : null;
    final weightKg = influxWeightKg ?? user.weightKG;

    PolarKcalBreakdown? polar;
    if (isPolarActive) {
      polar = PolarKcalBreakdown(
        weightKg: weightKg,
        weightFromInflux: influxWeightKg != null,
        bmrKcal: PolarBmrCalc.getBMRMifflinStJeor1990(
          user.copyWith(weightKG: weightKg),
        ),
        polarActiveKcal:
            await _polarDataSource.fetchActiveKcalForDate(DateTime.now()) ?? 0,
        activityKcal: upstream.activityKcal,
        manualKcalAdjustment: config.userKcalAdjustment ?? 0,
      );
    }

    final totalKcalGoal = polar?.totalKcalGoal ?? upstream.totalKcalGoal;
    final proteinGPerKg = await _polarDataSource.getProteinGPerKg();
    final fatGPerKg = await _polarDataSource.getFatGPerKg();
    final proteins = MacroCalc.getProteinGoalFromBodyWeight(
      weightKg,
      proteinGPerKg,
    );
    final fats = MacroCalc.getFatGoalFromBodyWeight(weightKg, fatGPerKg);
    return ForkGoalBreakdown(
      polar: polar,
      bodyWeightMacros: BodyWeightMacroBreakdown(
        totalKcalGoal: totalKcalGoal,
        weightKg: weightKg,
        proteinGPerKg: proteinGPerKg,
        fatGPerKg: fatGPerKg,
        proteinsGrams: proteins,
        fatsGrams: fats,
        carbsGrams: MacroCalc.getCarbsGoalBodyWeightBased(
          totalKcalGoal,
          proteins,
          fats,
        ),
      ),
    );
  }
}
