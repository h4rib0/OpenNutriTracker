import 'dart:io';

import 'package:equatable/equatable.dart';
import 'package:opennutritracker/core/data/dbo/meal_dbo.dart';
import 'package:opennutritracker/core/utils/id_generator.dart';
import 'package:opennutritracker/core/utils/supported_language.dart';
import 'package:opennutritracker/features/add_meal/data/dto/fdc/fdc_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/fdc/fdc_food_dto.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sp/sp_food_dto.dart';
import 'package:opennutritracker/features/add_meal/data/dto/off/off_product_dto.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_nutriments_entity.dart';

class MealEntity extends Equatable {
  static const liquidUnits = {'ml', 'l', 'dl', 'cl', 'fl oz', 'fl.oz'};
  static const solidUnits = {'kg', 'g', 'mg', 'µg', 'oz'};

  final String? code;
  final String? name;

  final String? brands;

  final String? thumbnailImageUrl;
  final String? mainImageUrl;

  final String? url;

  final String? mealQuantity;
  final String? mealUnit;
  final double? servingQuantity;
  final String? servingUnit;
  final String? servingSize;

  // Issue #158: many OFF products carry serving data (servingQuantity or
  // servingSize) but no overall package `quantity`, which left `servingUnit`
  // null and made the meal-detail dropdown default to 100 g/ml on every
  // scan. Treat a product as having serving values when either side of the
  // OFF data is present — the dropdown text in `_getServingDropdownItem`
  // already falls back to `servingSize` when `servingUnit` is missing.
  bool get hasServingValues => servingQuantity != null || servingSize != null;

  final MealSourceEntity source;

  /// Backend food_source.code ('fdc_sr_legacy', 'bls', 'indb'...) for
  /// meals from the Supabase backend, null for OFF/custom/recipe meals
  /// and legacy cached entries. Persisted so the UI can name the actual
  /// database a food came from (see SPConst.foodSourceDisplayNames) even
  /// though [source] groups them all under [MealSourceEntity.fdc].
  final String? backendSource;

  /// Relative path (`meal_images/<code>.webp`) to a user-attached photo
  /// for a custom meal, or null if none is set. Resolved to an absolute
  /// path at render time via `MealImageStorage.absolutePath`. Always
  /// null for OFF / FDC / recipe-derived meals — those carry remote URLs
  /// in `thumbnailImageUrl` / `mainImageUrl` instead.
  final String? localImagePath;

  final MealNutrimentsEntity nutriments;

  /// Whether this meal carries the full product record (serving fields and
  /// micronutrients). Open Food Facts text search now comes from the
  /// Search-a-licious index, which only returns a thin projection
  /// (`detailed == false`); opening such a result hydrates it to the full
  /// record via the v2 product endpoint (`detailed == true`). Barcode scans
  /// and FDC/custom meals are always full. See [hasServingValues] and the
  /// hydration step in MealDetailBloc.
  final bool detailed;

  bool get isLiquid => liquidUnits.contains(mealUnit);

  bool get isSolid => solidUnits.contains(mealUnit);

  const MealEntity({
    required this.code,
    required this.name,
    this.brands,
    this.thumbnailImageUrl,
    this.mainImageUrl,
    required this.url,
    required this.mealQuantity,
    required this.mealUnit,
    required this.servingQuantity,
    required this.servingUnit,
    required this.servingSize,
    required this.nutriments,
    required this.source,
    this.backendSource,
    this.localImagePath,
    this.detailed = false,
  });

  factory MealEntity.empty() => MealEntity(
        code: IdGenerator.getUniqueID(),
        name: null,
        url: null,
        mealQuantity: null,
        mealUnit: 'gml',
        servingQuantity: null,
        servingUnit: 'gml',
        servingSize: '',
        nutriments: MealNutrimentsEntity.empty(),
        source: MealSourceEntity.custom,
      );

  factory MealEntity.fromMealDBO(MealDBO mealDBO) => MealEntity(
        code: mealDBO.code,
        name: mealDBO.name,
        brands: mealDBO.brands,
        thumbnailImageUrl: mealDBO.thumbnailImageUrl,
        mainImageUrl: mealDBO.mainImageUrl,
        url: mealDBO.url,
        mealQuantity: mealDBO.mealQuantity,
        mealUnit: mealDBO.mealUnit,
        servingQuantity: mealDBO.servingQuantity,
        servingUnit: mealDBO.servingUnit,
        servingSize: mealDBO.servingSize,
        nutriments:
            MealNutrimentsEntity.fromMealNutrimentsDBO(mealDBO.nutriments),
        source: MealSourceEntity.fromMealSourceDBO(mealDBO.source),
        backendSource: mealDBO.backendSource,
        localImagePath: mealDBO.localImagePath,
        detailed: mealDBO.detailed ?? false,
      );

  /// [detailed] is true for full-product responses (the v2 barcode endpoint),
  /// false for the thin Search-a-licious text-search projection.
  factory MealEntity.fromOFFProduct(
    OFFProductDTO offProduct, {
    bool detailed = false,
  }) {
    return MealEntity(
      code: offProduct.code,
      name: offProduct.getLocaleName(
        SupportedLanguage.fromCode(Platform.localeName),
      ),
      brands: offProduct.brands,
      thumbnailImageUrl: offProduct.image_front_thumb_url,
      mainImageUrl: offProduct.image_front_url,
      url: offProduct.url,
      mealQuantity: offProduct.product_quantity?.toString(),
      mealUnit: _tryGetUnit(offProduct.quantity),
      servingQuantity: _tryQuantityCast(offProduct.serving_quantity),
      servingUnit: _tryGetUnit(offProduct.quantity),
      servingSize: offProduct.serving_size,
      nutriments: MealNutrimentsEntity.fromOffNutriments(offProduct.nutriments),
      source: MealSourceEntity.off,
      detailed: detailed,
    );
  }

  factory MealEntity.fromFDCFood(FDCFoodDTO fdcFood) {
    final fdcId = fdcFood.fdcId?.toInt().toString();

    return MealEntity(
      code: fdcId,
      name: fdcFood.description,
      brands: fdcFood.brandName,
      url: FDCConst.getFoodDetailUrlString(fdcId),
      mealQuantity: fdcFood.packageWeight,
      mealUnit: fdcFood.servingSizeUnit,
      servingQuantity: fdcFood.servingSize,
      servingUnit: fdcFood.servingSizeUnit,
      servingSize: fdcFood.servingSizeUnit,
      nutriments: MealNutrimentsEntity.fromFDCNutriments(fdcFood.foodNutrients),
      source: MealSourceEntity.fdc,
    );
  }

  factory MealEntity.fromSpFood(SpFoodDTO foodItem) {
    return MealEntity(
      code: foodItem.foodId?.toString(),
      name: foodItem.displayName,
      brands: foodItem.brands,
      // Only USDA FDC foods have a public detail page to link to; foods
      // from the other backend sources (BLS, INDB, TBCA...) link nowhere.
      url: foodItem.isFdc
          ? FDCConst.getFoodDetailUrlString(foodItem.sourceCode)
          : null,
      mealQuantity: null,
      mealUnit: FDCConst.fdcDefaultUnit,
      servingQuantity: foodItem.servingGramWeight,
      servingUnit: FDCConst.fdcDefaultUnit,
      servingSize: _spServingLabel(foodItem),
      nutriments: MealNutrimentsEntity.fromSpFoodSummary(foodItem),
      // All Supabase backend foods keep the fdc source tag: MealSourceDBO
      // is persisted in Hive, so a per-source enum value would need a data
      // migration. `fdc` here means "reference food database" as opposed
      // to OFF/custom; the true origin is carried in [backendSource].
      source: MealSourceEntity.fdc,
      backendSource: foodItem.source,
    );
  }

  /// Human-readable default-serving label ("1 cup", "2 slices"), falling
  /// back to the serving weight in grams when the portion has no
  /// description.
  static String? _spServingLabel(SpFoodDTO foodItem) {
    if (foodItem.servingSize != null) return foodItem.servingSize;
    final quantity = foodItem.servingQuantity;
    final unit = foodItem.servingUnit;
    if (quantity != null && unit != null) {
      return '${_formatAmount(quantity)} $unit';
    }
    final gramWeight = foodItem.servingGramWeight;
    if (gramWeight != null) return '${_formatAmount(gramWeight)} g';
    return null;
  }

  static String _formatAmount(double value) => value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toString();

  /// Value returned from OFF can either be String, int or double.
  /// Try casting it to a double value for calculation
  static double? _tryQuantityCast(dynamic value) {
    double? parsedValue;

    if (value == null) {
      parsedValue = null;
    } else if (value is double) {
      parsedValue = value;
    } else if (value is int) {
      parsedValue = value.toDouble();
    } else if (value is String) {
      value.replaceAll(RegExp("mg|g|kg|ml|cl|l| "), ""); // TODO extract
      final doubleParsed =
          double.tryParse(value) ?? int.tryParse(value)?.toDouble();
      parsedValue = doubleParsed;
    }
    return parsedValue;
  }

  /// TODO extract correct unit
  /// Unit can either be 100g or 100ml
  static String? _tryGetUnit(String? quantityString) {
    if (quantityString == null) return null;

    final isLiter = quantityString.toUpperCase().contains("L");

    if (isLiter) {
      return "ml";
    } else {
      return "g";
    }
  }

  @override
  List<Object?> get props => [code, name];
}

enum MealSourceEntity {
  unknown,
  custom,
  off,
  fdc,
  recipe,
  // Fork-only, read-only: see MealSourceDBO.sfcd.
  sfcd;

  factory MealSourceEntity.fromMealSourceDBO(MealSourceDBO mealSourceDBO) {
    MealSourceEntity mealSourceEntity;
    switch (mealSourceDBO) {
      case MealSourceDBO.unknown:
        mealSourceEntity = MealSourceEntity.unknown;
        break;
      case MealSourceDBO.custom:
        mealSourceEntity = MealSourceEntity.custom;
        break;
      case MealSourceDBO.off:
        mealSourceEntity = MealSourceEntity.off;
        break;
      case MealSourceDBO.fdc:
        mealSourceEntity = MealSourceEntity.fdc;
        break;
      case MealSourceDBO.recipe:
        mealSourceEntity = MealSourceEntity.recipe;
        break;
      case MealSourceDBO.sfcd:
        mealSourceEntity = MealSourceEntity.sfcd;
        break;
    }
    return mealSourceEntity;
  }
}
