import 'dart:async';

import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:opennutritracker/core/data/data_source/recipe_supabase_data_source.dart';
import 'package:opennutritracker/core/data/dbo/recipe_dbo.dart';

class RecipeDataSource {
  final Box<RecipeDBO> _recipeBox;
  final RecipeSupabaseDataSource? _supabase;

  RecipeDataSource(this._recipeBox, [this._supabase]);

  // Upsert by stable id. Recipe ids are uuids assigned at first save and
  // never change, so we can safely overwrite the matching record.
  Future<void> saveRecipe(RecipeDBO recipe) async {
    final existing = _recipeBox.values.cast<RecipeDBO?>().firstWhere(
          (r) => r?.id == recipe.id,
          orElse: () => null,
        );
    if (existing != null) {
      await _recipeBox.put(existing.key, recipe);
    } else {
      await _recipeBox.add(recipe);
    }
    unawaited(_supabase?.upsert(recipe));
  }

  List<RecipeDBO> getAllRecipes() => _recipeBox.values.toList();

  RecipeDBO? getRecipeById(String id) {
    for (final recipe in _recipeBox.values) {
      if (recipe.id == id) return recipe;
    }
    return null;
  }

  Future<void> deleteRecipe(String id) async {
    final toDelete = _recipeBox.values.where((r) => r.id == id).toList();
    for (final recipe in toDelete) {
      await recipe.delete();
    }
    unawaited(_supabase?.delete(id));
  }

  /// Fetches recipes from Supabase and saves any that are missing locally.
  /// Called once at startup to restore data after a reinstall.
  Future<void> syncFromSupabase() async {
    final remote = await _supabase?.fetchAll() ?? [];
    if (remote.isEmpty) return;
    final localIds = _recipeBox.values.map((r) => r.id).toSet();
    for (final recipe in remote) {
      if (!localIds.contains(recipe.id)) {
        await _recipeBox.add(recipe);
      }
    }
  }
}
