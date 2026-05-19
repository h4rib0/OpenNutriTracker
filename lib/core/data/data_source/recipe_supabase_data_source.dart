import 'package:logging/logging.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Syncs user-created recipes to Supabase so they survive a local cache
/// clear or app reinstall.
///
/// Table: user_recipes
///   user_id      UUID  (auth.uid())
///   recipe_id    TEXT  (stable UUID assigned at first save)
///   recipe_data  JSONB (full RecipeDBO as JSON)
///   updated_at   TIMESTAMPTZ
class RecipeSupabaseDataSource {
  static const _table = 'user_recipes';

  final _log = Logger('RecipeSupabaseDataSource');
  final SupabaseClient _client;

  RecipeSupabaseDataSource(this._client);

  Future<void> upsert(RecipeDBO recipe) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client.from(_table).upsert(
        {
          'user_id': userId,
          'recipe_id': recipe.id,
          'recipe_data': recipe.toJson(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id,recipe_id',
      );
      _log.fine('Upserted recipe: ${recipe.id}');
    } catch (e) {
      _log.warning('Failed to upsert recipe ${recipe.id}: $e');
    }
  }

  Future<void> delete(String recipeId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _client
          .from(_table)
          .delete()
          .eq('user_id', userId)
          .eq('recipe_id', recipeId);
      _log.fine('Deleted recipe: $recipeId');
    } catch (e) {
      _log.warning('Failed to delete recipe $recipeId: $e');
    }
  }

  Future<List<RecipeDBO>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final rows = await _client.from(_table).select().eq('user_id', userId);
      return rows
          .map((r) => RecipeDBO.fromJson(r['recipe_data'] as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _log.warning('Failed to fetch recipes: $e');
      return [];
    }
  }
}
