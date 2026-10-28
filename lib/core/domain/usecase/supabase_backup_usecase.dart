import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/data_source/custom_meal_data_source.dart';
import 'package:opennutritracker/core/data/data_source/nutrient_override_data_source.dart';
import 'package:opennutritracker/core/data/data_source/recipe_data_source.dart';
import 'package:opennutritracker/core/data/data_source/remote_search_cache_data_source.dart';
import 'package:opennutritracker/core/data/data_source/supabase_recovery_data_source.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/data/dbo/meal_nutriments_dbo.dart';
import 'package:opennutritracker/core/data/repository/config_repository.dart';

/// Fork-only: the Supabase backup of custom meals, recipes and nutrient
/// overrides — pulling it onto the device and re-attaching it to a new
/// install with the recovery code.
class SupabaseBackupUsecase {
  final _log = Logger('SupabaseBackupUsecase');

  final NutrientOverrideDataSource _overrideDataSource;
  final CustomMealDataSource _customMealDataSource;
  final RecipeDataSource _recipeDataSource;
  final RemoteSearchCacheDataSource _remoteSearchCache;
  final ConfigRepository _configRepository;
  final SupabaseRecoveryDataSource _recoveryDataSource;

  SupabaseBackupUsecase(
    this._overrideDataSource,
    this._customMealDataSource,
    this._recipeDataSource,
    this._remoteSearchCache,
    this._configRepository,
    this._recoveryDataSource,
  );

  /// Startup: signs in anonymously, pulls the backup and registers this
  /// install's recovery code.
  Future<void> initOnStartup() async {
    await _overrideDataSource.ensureSignedIn();
    await pull();
    await _recoveryDataSource.ensureRegistered();
  }

  /// Restores custom meals and recipes missing on the device and, when the
  /// user has opted in, merges the nutrient overrides into the local
  /// search cache so manually entered values survive a cache clear.
  Future<void> pull() async {
    // Custom meals and recipes run regardless of syncNutrientsToSupabase.
    await _customMealDataSource.syncFromSupabase();
    await _recipeDataSource.syncFromSupabase();

    final config = await _configRepository.getConfig();
    if (!config.syncNutrientsToSupabase) return;

    final overrides = await _overrideDataSource.fetchAll();
    if (overrides.isEmpty) return;

    final existing = _remoteSearchCache.getAll();
    for (final override in overrides) {
      final matches = existing.where(
        (m) =>
            (m.code == override.lookupKey || m.name == override.lookupKey) &&
            m.source.name == override.mealSource,
      );
      // Not in the cache: can't enrich without the full meal data.
      if (matches.isEmpty) continue;

      final match = matches.first;
      if (_hasNutrients(match)) continue; // already enriched

      await _remoteSearchCache.cache(
        MealDBO(
          code: match.code,
          name: match.name,
          brands: match.brands,
          url: match.url,
          thumbnailImageUrl: match.thumbnailImageUrl,
          mainImageUrl: match.mainImageUrl,
          mealQuantity: match.mealQuantity,
          mealUnit: match.mealUnit,
          servingQuantity: match.servingQuantity,
          servingUnit: match.servingUnit,
          servingSize: match.servingSize,
          nutriments: MealNutrimentsDBO(
            energyKcal100: override.kcal100,
            carbohydrates100: override.carbs100,
            fat100: override.fat100,
            proteins100: override.proteins100,
            sugars100: match.nutriments.sugars100,
            saturatedFat100: match.nutriments.saturatedFat100,
            fiber100: match.nutriments.fiber100,
          ),
          source: match.source,
        ),
      );
    }
  }

  /// The current install's recovery code, registering one if needed. Null
  /// while offline or not signed in.
  Future<String?> getRecoveryCode() => _recoveryDataSource.ensureRegistered();

  /// The registered code without touching the network.
  Future<String?> getRegisteredRecoveryCode() =>
      _recoveryDataSource.getRegisteredCode();

  /// Claims [code] and pulls what it brought along. Returns the number of
  /// rows moved on the server, or null when the code is unknown. See
  /// [SupabaseRecoveryDataSource.claim] for what it throws.
  Future<int?> restoreWithCode(String code) async {
    await _overrideDataSource.ensureSignedIn();
    final moved = await _recoveryDataSource.claim(code);
    if (moved == null) return null;
    _log.info('Recovery code claimed, $moved rows moved');
    await pull();
    return moved;
  }

  static bool _hasNutrients(MealDBO meal) {
    final kcal = meal.nutriments.energyKcal100;
    return kcal != null && kcal > 0;
  }
}
