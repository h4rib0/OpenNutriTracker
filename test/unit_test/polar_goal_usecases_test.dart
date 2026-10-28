import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_data_source.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/user_repository.dart';
import 'package:opennutritracker/core/domain/entity/app_theme_entity.dart';
import 'package:opennutritracker/core/domain/entity/config_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_macro_goal_usecase.dart';
import 'package:opennutritracker/core/utils/calc/polar_bmr_calc.dart';
import 'package:opennutritracker/core/utils/calc/calorie_goal_calc.dart';

import '../fixture/user_entity_fixtures.dart';
import '../helpers/fake_hive_db_provider.dart';

class _FakeConfigRepository extends ConfigRepository {
  final ConfigEntity config;

  _FakeConfigRepository(this.config)
    : super(ConfigDataSource(FakeHiveDBProvider()));

  @override
  Future<ConfigEntity> getConfig() async => config;
}

class _FakeUserRepository extends UserRepository {
  final UserEntity user;

  _FakeUserRepository(this.user) : super(UserDataSource(FakeHiveDBProvider()));

  @override
  Future<UserEntity> getUserData() async => user;
}

class _FakePolar extends PolarInfluxdbDataSource {
  final bool configured;
  final double? weightKg;
  final double? activeKcal;

  _FakePolar({this.configured = true, this.weightKg, this.activeKcal});

  @override
  Future<bool> isPolarConfigured() async => configured;
  @override
  Future<double?> fetchLatestWeightKg() async => weightKg;
  @override
  Future<double?> fetchActiveKcalForDate(DateTime date) async => activeKcal;
  @override
  Future<double> getProteinGPerKg() async =>
      GetMacroGoalUsecase.defaultProteinGPerKg;
  @override
  Future<double> getFatGPerKg() async => GetMacroGoalUsecase.defaultFatGPerKg;
}

ConfigEntity _config({
  double? kcalAdjustment,
  bool useBodyWeightMacros = false,
}) => ConfigEntity(
  true,
  true,
  false,
  AppThemeEntity.system,
  userKcalAdjustment: kcalAdjustment,
  useBodyWeightMacros: useBodyWeightMacros,
);

void main() {
  final user =
      UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight; // 80 kg
  final activityRepo = UserActivityRepository(
    UserActivityDataSource(FakeHiveDBProvider()),
  );

  group('GetKcalGoalUsecase with Polar', () {
    GetKcalGoalUsecase usecase(
      ConfigEntity config, [
      PolarInfluxdbDataSource? polar,
    ]) => GetKcalGoalUsecase(
      _FakeUserRepository(user),
      _FakeConfigRepository(config),
      activityRepo,
      polar,
    );

    test(
      'BMR + Polar active kcal + logged activities + signed slider',
      () async {
        final polar = _FakePolar(weightKg: 78, activeKcal: 600);
        final goal = await usecase(
          _config(kcalAdjustment: -500),
          polar,
        ).getKcalGoal(totalKcalActivitiesParam: 200);

        final bmr = PolarBmrCalc.getBMRMifflinStJeor1990(
          user.copyWith(weightKG: 78),
        );
        expect(goal, closeTo(bmr + 600 + 200 - 500, 0.001));
      },
    );

    test(
      'falls back to the profile weight and 0 active kcal without InfluxDB data',
      () async {
        final goal = await usecase(
          _config(kcalAdjustment: 300),
          _FakePolar(),
        ).getKcalGoal(totalKcalActivitiesParam: 0);

        expect(
          goal,
          closeTo(PolarBmrCalc.getBMRMifflinStJeor1990(user) + 300, 0.001),
        );
      },
    );

    test(
      'uses the regular goal when Polar is not configured or not passed',
      () async {
        final expected = CalorieGoalCalc.getTotalKcalGoal(
          user,
          0,
          kcalUserAdjustment: 100,
        );

        final notConfigured = await usecase(
          _config(kcalAdjustment: 100),
          _FakePolar(configured: false),
        ).getKcalGoal(totalKcalActivitiesParam: 0);
        final withoutPolar = await usecase(
          _config(kcalAdjustment: 100),
        ).getKcalGoal(totalKcalActivitiesParam: 0);

        expect(notConfigured, closeTo(expected, 0.001));
        expect(withoutPolar, closeTo(expected, 0.001));
      },
    );
  });

  group('GetMacroGoalUsecase body-weight mode', () {
    const kcal = 2500.0;

    test(
      'Polar configured: 2.2 g/kg protein, 0.8 g/kg fat from InfluxDB weight, carbs fill the rest',
      () async {
        final goals = await GetMacroGoalUsecase(
          _FakeConfigRepository(_config()),
          _FakeUserRepository(user),
          _FakePolar(weightKg: 75),
        ).getMacroGoals(kcal);

        expect(goals.proteins, closeTo(2.2 * 75, 0.001));
        expect(goals.fats, closeTo(0.8 * 75, 0.001));
        expect(
          goals.carbs,
          closeTo((kcal - 2.2 * 75 * 4 - 0.8 * 75 * 9) / 4, 0.001),
        );
      },
    );

    test('opt-in without Polar uses the profile weight', () async {
      final goals = await GetMacroGoalUsecase(
        _FakeConfigRepository(_config(useBodyWeightMacros: true)),
        _FakeUserRepository(user),
        _FakePolar(configured: false, weightKg: 60),
      ).getMacroGoals(kcal);

      expect(goals.proteins, closeTo(2.2 * 80, 0.001));
      expect(goals.fats, closeTo(0.8 * 80, 0.001));
    });

    test('default is the % split', () async {
      final usecase = GetMacroGoalUsecase(
        _FakeConfigRepository(_config()),
        _FakeUserRepository(user),
        _FakePolar(configured: false),
      );
      final goals = await usecase.getMacroGoals(kcal);

      expect(goals.carbs, closeTo(kcal * 0.6 / 4, 0.001));
      expect(goals.fats, closeTo(kcal * 0.25 / 9, 0.001));
      expect(goals.proteins, closeTo(kcal * 0.15 / 4, 0.001));
      expect(await usecase.getProteinsGoal(kcal), goals.proteins);
    });
  });
}
