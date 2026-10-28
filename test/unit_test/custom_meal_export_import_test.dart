import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:opennutritracker/core/data/data_source/config_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_activity_template_dbo.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_supabase_data_source.dart';
import 'package:opennutritracker/core/data/data_source/favourite_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/intake_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/tracked_day_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_data_source.dart';
import 'package:opennutritracker/core/data/data_source/user_activity_dbo.dart';
import 'package:opennutritracker/core/data/data_source/weight_log_data_source.dart';
import 'package:opennutritracker/core/data/dbo/config_dbo.dart';
import 'package:opennutritracker/core/data/dbo/favourite_meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/intake_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:opennutritracker/core/data/dbo/tracked_day_dbo.dart';
import 'package:opennutritracker/core/data/dbo/weight_log_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';
import 'package:opennutritracker/core/data/repository/custom_activity_template_repository.dart';
import 'package:opennutritracker/core/data/repository/favourite_meal_repository.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/data/repository/recipe_repository.dart';
import 'package:opennutritracker/core/data/repository/tracked_day_repository.dart';
import 'package:opennutritracker/core/data/repository/user_activity_repository.dart';
import 'package:opennutritracker/core/data/repository/weight_log_repository.dart';
import 'package:opennutritracker/core/domain/usecase/supabase_backup_usecase.dart';
import 'package:opennutritracker/features/settings/domain/usecase/export_data_usecase.dart';
import 'package:opennutritracker/features/settings/domain/usecase/import_data_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/export_import_bloc.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/fake_hive_db_provider.dart';
import '../helpers/hive_test_setup.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.root);

  final String root;

  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

/// Same shape as `favourite_export_import_test.dart`.
final class _PickedFile extends PlatformFile {
  _PickedFile(this.name, this.uri);

  @override
  final String name;

  @override
  final Uri uri;

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => null;

  @override
  Future<int> length() => File(path!).length();

  @override
  Future<Uint8List> readAsBytes() => File(path!).readAsBytes();

  @override
  Stream<Uint8List> readAsByteStream() => File(path!).openRead().cast();
}

/// Records what would have gone to Supabase instead of sending it.
class _RecordingSupabase extends CustomMealSupabaseDataSource {
  _RecordingSupabase()
    : super(SupabaseClient('http://backend.invalid', 'test-key'));

  final upserted = <String?>[];
  final deleted = <String>[];

  @override
  Future<void> upsert(MealDBO meal) async =>
      upserted.add(meal.code ?? meal.name);

  @override
  Future<void> delete(String lookupKey) async => deleted.add(lookupKey);
}

/// Stands in for the Supabase backup: a fixed code, and records claims.
class _FakeBackup implements SupabaseBackupUsecase {
  _FakeBackup({this.code, this.claimThrows = false});

  final String? code;
  final bool claimThrows;
  final claimed = <String>[];

  @override
  Future<String?> getRecoveryCode() async => code;

  @override
  Future<String?> getRegisteredRecoveryCode() async => code;

  @override
  Future<int?> restoreWithCode(String code) async {
    claimed.add(code);
    if (claimThrows) throw Exception('offline');
    return 3;
  }

  @override
  Future<void> initOnStartup() async {}

  @override
  Future<void> pull() async {}
}

// Every dataset but custom meals is empty on both legs.
final _boxless = FakeHiveDBProvider();

class _EmptyUserActivityRepository extends UserActivityRepository {
  _EmptyUserActivityRepository() : super(UserActivityDataSource(_boxless));

  @override
  Future<List<UserActivityDBO>> getAllUserActivityDBO() async => [];

  @override
  Future<void> upsertAllUserActivityDBOs(List<UserActivityDBO> dbos) async {}
}

class _EmptyIntakeRepository extends IntakeRepository {
  _EmptyIntakeRepository() : super(IntakeDataSource(_boxless));

  @override
  Future<List<IntakeDBO>> getAllIntakesDBO() async => [];

  @override
  Future<void> upsertAllIntakeDBOs(List<IntakeDBO> intakeDBOs) async {}
}

class _EmptyTrackedDayRepository extends TrackedDayRepository {
  _EmptyTrackedDayRepository() : super(TrackedDayDataSource(_boxless));

  @override
  Future<List<TrackedDayDBO>> getAllTrackedDaysDBO() async => [];

  @override
  Future<void> addAllTrackedDays(List<TrackedDayDBO> trackedDaysDBO) async {}
}

class _EmptyRecipeRepository extends RecipeRepository {
  _EmptyRecipeRepository() : super(RecipeDataSource(_boxless));

  @override
  List<RecipeDBO> getAllRecipesDBO() => [];

  @override
  Future<void> addAllRecipeDBOs(List<RecipeDBO> recipes) async {}
}

class _EmptyWeightLogRepository extends WeightLogRepository {
  _EmptyWeightLogRepository() : super(WeightLogDataSource(_boxless));

  @override
  Future<List<WeightLogDBO>> getAllEntriesDBO() async => [];

  @override
  Future<void> addAllEntries(List<WeightLogDBO> entries) async {}
}

class _EmptyTemplateRepository extends CustomActivityTemplateRepository {
  _EmptyTemplateRepository()
    : super(CustomActivityTemplateDataSource(_boxless));

  @override
  Future<List<CustomActivityTemplateDBO>> allTemplateDBOs() async => [];

  @override
  Future<void> upsertAllTemplateDBOs(
    List<CustomActivityTemplateDBO> templates,
  ) async {}
}

class _EmptyConfigRepository extends ConfigRepository {
  _EmptyConfigRepository() : super(ConfigDataSource(_boxless));

  @override
  Future<ConfigDBO> getConfigDBO() async => ConfigDBO.empty();

  @override
  Future<void> setConfigGoalSettings({
    required double? kcalAdjustment,
    required double? carbGoalPct,
    required double? proteinGoalPct,
    required double? fatGoalPct,
    required Map<String, int>? mealKcalSharesPct,
    required int? dailyWaterGoalMl,
  }) async {}
}

class _EmptyFavouriteMealRepository extends FavouriteMealRepository {
  _EmptyFavouriteMealRepository()
    : super(
        FavouriteMealDataSource(_boxless),
        CustomMealDataSource(_boxless),
        RecipeDataSource(_boxless),
      );

  @override
  Future<List<FavouriteMealDBO>> getAllFavouritesDBO() async => [];

  @override
  Future<void> addAllFavouriteDBOs(List<FavouriteMealDBO> favourites) async {}
}

MealDBO _meal({String? code, required String name, double kcal = 100}) =>
    MealDBO(
      code: code,
      name: name,
      brands: null,
      thumbnailImageUrl: null,
      mainImageUrl: null,
      url: null,
      mealQuantity: '100',
      mealUnit: 'g',
      servingQuantity: null,
      servingUnit: 'g',
      servingSize: null,
      nutriments: MealNutrimentsDBO(
        energyKcal100: kcal,
        carbohydrates100: 4,
        fat100: 5,
        proteins100: 10,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      ),
      source: MealSourceDBO.custom,
    );

/// Fork: the custom meal / food library rides along in the JSON bundle and
/// comes back on import (upstream only exports the meals' photos).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempRoot;
  late PathProviderPlatform originalPathProvider;
  late Box<MealDBO> sourceBox;
  late Box<MealDBO> targetBox;

  setUpAll(() {
    Hive.init('.');
    registerHiveAdaptersOnce();
  });

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('ont_custom_meals_');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempRoot.path);
    final tag = DateTime.now().microsecondsSinceEpoch;
    sourceBox = await Hive.openBox<MealDBO>('custom_export_$tag');
    targetBox = await Hive.openBox<MealDBO>('custom_import_$tag');
  });

  tearDown(() async {
    PathProviderPlatform.instance = originalPathProvider;
    await sourceBox.deleteFromDisk();
    await targetBox.deleteFromDisk();
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  Future<Archive> exportFrom(
    CustomMealDataSource customMeals, {
    SupabaseBackupUsecase? backup,
  }) =>
      ExportDataUsecase(
        _EmptyUserActivityRepository(),
        _EmptyIntakeRepository(),
        _EmptyTrackedDayRepository(),
        _EmptyRecipeRepository(),
        customMeals,
        _EmptyWeightLogRepository(),
        _EmptyTemplateRepository(),
        _EmptyConfigRepository(),
        _EmptyFavouriteMealRepository(),
        backup,
      ).assembleArchive(
        format: ExportFormat.json,
        userActivityJsonFileName: ExportImportBloc.userActivityJsonFileName,
        userIntakeJsonFileName: ExportImportBloc.userIntakeJsonFileName,
        trackedDayJsonFileName: ExportImportBloc.trackedDayJsonFileName,
        recipeJsonFileName: ExportImportBloc.recipeJsonFileName,
        weightLogJsonFileName: ExportImportBloc.weightLogJsonFileName,
        customActivityTemplateJsonFileName:
            ExportImportBloc.customActivityTemplateJsonFileName,
      );

  Future<bool> importInto(
    CustomMealDataSource customMeals,
    Archive archive, {
    SupabaseBackupUsecase? backup,
  }) {
    final zip = File('${tempRoot.path}/backup.zip')
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    return ImportDataUsecase(
      _EmptyUserActivityRepository(),
      _EmptyIntakeRepository(),
      _EmptyTrackedDayRepository(),
      _EmptyRecipeRepository(),
      _EmptyWeightLogRepository(),
      _EmptyTemplateRepository(),
      _EmptyConfigRepository(),
      _EmptyFavouriteMealRepository(),
      pickFile: () async => _PickedFile('backup.zip', zip.uri),
      customMealDataSource: customMeals,
      supabaseBackupUsecase: backup,
    ).importData(
      ExportImportBloc.userActivityJsonFileName,
      ExportImportBloc.userIntakeJsonFileName,
      ExportImportBloc.trackedDayJsonFileName,
      ExportImportBloc.recipeJsonFileName,
      ExportImportBloc.weightLogJsonFileName,
      ExportImportBloc.customActivityTemplateJsonFileName,
    );
  }

  test('a JSON export carries the custom meals and an import restores them '
      'and pushes them to Supabase', () async {
    final exporting = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: sourceBox),
    );
    await exporting.saveCustomMeal(_meal(code: '4001', name: 'Skyr'));
    await exporting.saveCustomMeal(_meal(name: 'Greek yoghurt', kcal: 97));

    final archive = await exportFrom(exporting);
    final entry = archive.findFile(ExportDataUsecase.customMealJsonFileName);
    expect(entry, isNotNull);
    expect(jsonDecode(utf8.decode(entry!.content as List<int>)), hasLength(2));

    final supabase = _RecordingSupabase();
    final importing = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: targetBox),
      supabase,
    );
    expect(await importInto(importing, archive), isTrue);

    final restored = importing.getAllCustomMeals();
    expect(restored.map((m) => m.name), ['Skyr', 'Greek yoghurt']);
    expect(restored.last.nutriments.energyKcal100, 97);
    expect(supabase.upserted, ['4001', 'Greek yoghurt']);
  });

  test('importing the same bundle twice does not duplicate', () async {
    final exporting = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: sourceBox),
    );
    await exporting.saveCustomMeal(_meal(code: '4001', name: 'Skyr'));
    final archive = await exportFrom(exporting);

    final importing = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: targetBox),
    );
    await importInto(importing, archive);
    await importInto(importing, archive);

    expect(importing.getAllCustomMeals(), hasLength(1));
  });

  test('a bundle without the entry leaves the library untouched', () async {
    final archive = await exportFrom(
      CustomMealDataSource(FakeHiveDBProvider(customMealBox: sourceBox)),
    );
    final withoutMeals = Archive();
    for (final file in archive.files) {
      if (file.name != ExportDataUsecase.customMealJsonFileName) {
        withoutMeals.addFile(file);
      }
    }

    final importing = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: targetBox),
    );
    await importing.saveCustomMeal(_meal(name: 'Kept'));
    expect(await importInto(importing, withoutMeals), isTrue);

    expect(importing.getAllCustomMeals().map((m) => m.name), ['Kept']);
  });

  test('editing a custom meal syncs it and drops the old remote key', () async {
    final supabase = _RecordingSupabase();
    final ds = CustomMealDataSource(
      FakeHiveDBProvider(customMealBox: sourceBox),
      supabase,
    );
    final before = _meal(name: 'Oats');
    await ds.saveCustomMeal(before);

    await ds.saveCustomMeal(_meal(name: 'Oats', kcal: 370), previous: before);
    await ds.saveCustomMeal(
      _meal(code: '5000', name: 'Oats'),
      previous: _meal(name: 'Oats'),
    );

    expect(supabase.upserted, ['Oats', 'Oats', '5000']);
    expect(supabase.deleted, ['Oats']);
    expect(ds.getAllCustomMeals().single.code, '5000');
  });

  group('recovery code', () {
    const code = 'ABCD-EFGH-JKMN-PQRS-TVWX';

    test('a JSON export carries the code and an import claims it', () async {
      final archive = await exportFrom(
        CustomMealDataSource(FakeHiveDBProvider(customMealBox: sourceBox)),
        backup: _FakeBackup(code: code),
      );
      final entry = archive.findFile(
        ExportDataUsecase.recoveryCodeJsonFileName,
      );
      expect(entry, isNotNull);
      expect(jsonDecode(utf8.decode(entry!.content as List<int>)), {
        'code': code,
      });

      final backup = _FakeBackup();
      final imported = await importInto(
        CustomMealDataSource(FakeHiveDBProvider(customMealBox: targetBox)),
        archive,
        backup: backup,
      );
      expect(imported, isTrue);
      expect(backup.claimed, [code]);
    });

    test('no code (offline, not signed in) leaves the entry out', () async {
      final archive = await exportFrom(
        CustomMealDataSource(FakeHiveDBProvider(customMealBox: sourceBox)),
        backup: _FakeBackup(),
      );
      expect(
        archive.findFile(ExportDataUsecase.recoveryCodeJsonFileName),
        isNull,
      );
    });

    test('a failing claim does not fail the import', () async {
      final archive = await exportFrom(
        CustomMealDataSource(FakeHiveDBProvider(customMealBox: sourceBox)),
        backup: _FakeBackup(code: code),
      );
      final backup = _FakeBackup(claimThrows: true);
      final imported = await importInto(
        CustomMealDataSource(FakeHiveDBProvider(customMealBox: targetBox)),
        archive,
        backup: backup,
      );
      expect(imported, isTrue);
      expect(backup.claimed, [code]);
    });
  });
}
