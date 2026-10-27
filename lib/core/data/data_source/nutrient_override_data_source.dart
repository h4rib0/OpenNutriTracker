import 'package:logging/logging.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Persists user-supplied nutrient corrections for OFF/FDC products in
/// Supabase so they survive a local cache clear or app reinstall.
///
/// Requires Supabase Anonymous Auth to be active — call
/// [NutrientOverrideDataSource.ensureSignedIn] once at startup.
///
/// Table: user_nutrient_overrides
///   user_id      UUID  (auth.uid())
///   lookup_key   TEXT  (barcode when available, else product name)
///   meal_source  TEXT  ('off' or 'fdc')
///   kcal_100     NUMERIC
///   carbs_100    NUMERIC
///   fat_100      NUMERIC
///   proteins_100 NUMERIC
///   updated_at   TIMESTAMPTZ
class NutrientOverrideDataSource {
  static const _table = 'user_nutrient_overrides';

  final _log = Logger('NutrientOverrideDataSource');
  final SupabaseClient _client;

  NutrientOverrideDataSource(this._client);

  /// Signs in anonymously if no active session exists.
  /// Safe to call multiple times — no-op when already signed in.
  Future<void> ensureSignedIn() async {
    if (_client.auth.currentSession != null) return;
    try {
      await _client.auth.signInAnonymously();
      _log.fine('Signed in anonymously to Supabase');
    } catch (e) {
      _log.warning('Anonymous sign-in failed: $e');
    }
  }

  /// Persist (upsert) the user-supplied nutrient values for [meal].
  /// Does nothing when the meal has no kcal data or no identity key.
  Future<void> upsert(MealEntity meal) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final key = _lookupKey(meal);
    if (key == null) return;

    final n = meal.nutriments;
    if ((n.energyKcal100 ?? 0) <= 0) return;

    try {
      await _client.from(_table).upsert(
        {
          'user_id': userId,
          'lookup_key': key,
          'meal_source': meal.source.name,
          'kcal_100': n.energyKcal100,
          'carbs_100': n.carbohydrates100,
          'fat_100': n.fat100,
          'proteins_100': n.proteins100,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,meal_source,lookup_key',
      );
      _log.fine('Upserted nutrient override for $key');
    } catch (e) {
      _log.warning('Failed to upsert nutrient override: $e');
    }
  }

  /// Load all overrides for the current user from Supabase.
  /// Returns an empty list when not signed in or on error.
  Future<List<NutrientOverride>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final rows = await _client
          .from(_table)
          .select()
          .eq('user_id', userId);

      return rows.map((r) => NutrientOverride.fromJson(r)).toList();
    } catch (e) {
      _log.warning('Failed to fetch nutrient overrides: $e');
      return [];
    }
  }

  String? _lookupKey(MealEntity meal) {
    if (meal.code != null && meal.code!.isNotEmpty) return meal.code;
    if (meal.name != null && meal.name!.isNotEmpty) return meal.name;
    return null;
  }
}

class NutrientOverride {
  final String lookupKey;
  final String mealSource;
  final double? kcal100;
  final double? carbs100;
  final double? fat100;
  final double? proteins100;

  const NutrientOverride({
    required this.lookupKey,
    required this.mealSource,
    this.kcal100,
    this.carbs100,
    this.fat100,
    this.proteins100,
  });

  factory NutrientOverride.fromJson(Map<String, dynamic> json) =>
      NutrientOverride(
        lookupKey: json['lookup_key'] as String,
        mealSource: json['meal_source'] as String,
        kcal100: (json['kcal_100'] as num?)?.toDouble(),
        carbs100: (json['carbs_100'] as num?)?.toDouble(),
        fat100: (json['fat_100'] as num?)?.toDouble(),
        proteins100: (json['proteins_100'] as num?)?.toDouble(),
      );

  MealNutrimentsEntity toNutriments() => MealNutrimentsEntity(
        energyKcal100: kcal100,
        carbohydrates100: carbs100,
        fat100: fat100,
        proteins100: proteins100,
        sugars100: null,
        saturatedFat100: null,
        fiber100: null,
      );
}
