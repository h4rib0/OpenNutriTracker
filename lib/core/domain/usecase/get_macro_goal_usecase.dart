import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/utils/calc/macro_calc.dart';

typedef MacroGoals = ({double carbs, double fats, double proteins});

class GetMacroGoalUsecase {
  // Defaults for the body-weight mode, matching MacroSplitDialog.
  static const double defaultProteinGPerKg = 2.2;
  static const double defaultFatGPerKg = 0.8;

  final ConfigRepository _configRepository;
  // Both optional: without a user repository the body-weight mode can't run
  // and the % split is used; without Polar the body-weight mode only runs
  // when the user opted in (see ConfigEntity.useBodyWeightMacros).
  final UserRepository? _userRepository;
  final PolarInfluxdbDataSource? _polarDataSource;

  GetMacroGoalUsecase(this._configRepository, [this._userRepository, this._polarDataSource]);

  /// Protein and fat from body weight (g/kg) with carbs filling the rest of
  /// [totalCalorieGoal] — always while Polar is configured, otherwise when the
  /// user opted in. Falls back to the % split.
  Future<MacroGoals> getMacroGoals(double totalCalorieGoal, {UserEntity? userEntity}) async {
    final config = await _configRepository.getConfig();
    final polar = _polarDataSource;
    final isPolarActive = polar != null && await polar.isPolarConfigured();
    final userRepository = _userRepository;

    if (userRepository != null && (isPolarActive || config.useBodyWeightMacros)) {
      final user = userEntity ?? await userRepository.getUserData();
      final influxWeightKg = isPolarActive ? await polar.fetchLatestWeightKg() : null;
      final weightKg = influxWeightKg ?? user.weightKG;
      final proteinGPerKg = await polar?.getProteinGPerKg() ?? defaultProteinGPerKg;
      final fatGPerKg = await polar?.getFatGPerKg() ?? defaultFatGPerKg;
      final proteins = MacroCalc.getProteinGoalFromBodyWeight(weightKg, proteinGPerKg);
      final fats = MacroCalc.getFatGoalFromBodyWeight(weightKg, fatGPerKg);
      return (
        carbs: MacroCalc.getCarbsGoalBodyWeightBased(totalCalorieGoal, proteins, fats),
        fats: fats,
        proteins: proteins,
      );
    }

    return (
      carbs: MacroCalc.getTotalCarbsGoal(totalCalorieGoal, userCarbsGoal: config.userCarbGoalPct),
      fats: MacroCalc.getTotalFatsGoal(totalCalorieGoal, userFatsGoal: config.userFatGoalPct),
      proteins: MacroCalc.getTotalProteinsGoal(totalCalorieGoal, userProteinsGoal: config.userProteinGoalPct),
    );
  }

  Future<double> getCarbsGoal(double totalCalorieGoal) async => (await getMacroGoals(totalCalorieGoal)).carbs;

  Future<double> getFatsGoal(double totalCalorieGoal) async => (await getMacroGoals(totalCalorieGoal)).fats;

  Future<double> getProteinsGoal(double totalCalorieGoal) async => (await getMacroGoals(totalCalorieGoal)).proteins;
}
