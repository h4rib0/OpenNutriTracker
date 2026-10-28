import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:flutter/widgets.dart' show basicLocaleListResolution;
import 'package:opennutritracker/core/l10n/app_locales.dart';
import 'package:opennutritracker/core/utils/app_locale.dart';
import 'package:opennutritracker/core/utils/widget/calorie_widget_snapshot.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// The widgets' text, translated on the Dart side.
///
/// Neither the iOS extension nor the Android widgets can read the generated
/// Dart strings, and copy written in Swift or Android resources would sit
/// outside the ARB/Weblate pipeline. So the app writes the already-localized
/// labels next to the numbers, and the widgets fall back to English only
/// until the first write.
class CalorieWidgetLabels {
  /// The App Group key of the labels that depend only on the language, as
  /// one JSON string. They hold nothing about the profile, so a wipe keeps
  /// them and the placeholder stays translated. The labels that carry the
  /// figures travel inside the snapshot instead
  /// ([CalorieWidgetSnapshot.encode]), so they always describe it.
  static const storageKey = 'ont_calorie_labels';

  final String title;
  final String unit;
  final String goal;
  final String accessibility;
  final String openApp;
  final String description;

  /// The rest is read by the Android widgets only.
  final String kcalLeft;
  final String kcalOver;
  final String goalTitle;
  final String supplied;
  final String burned;
  final String carbsShort;
  final String fatShort;
  final String proteinShort;
  final String gram;
  final String water;
  final String ml;
  final String breakfast;
  final String lunch;
  final String dinner;
  final String snack;
  final String add;

  const CalorieWidgetLabels({
    required this.title,
    required this.unit,
    required this.goal,
    required this.accessibility,
    required this.openApp,
    required this.description,
    this.kcalLeft = 'kcal left',
    this.kcalOver = 'kcal too much',
    this.goalTitle = 'Goal',
    this.supplied = 'supplied',
    this.burned = 'burned',
    this.carbsShort = 'C',
    this.fatShort = 'F',
    this.proteinShort = 'P',
    this.gram = 'g',
    this.water = 'Water',
    this.ml = 'ml',
    this.breakfast = 'Breakfast',
    this.lunch = 'Lunch',
    this.dinner = 'Dinner',
    this.snack = 'Snack',
    this.add = 'Add',
  });

  /// The labels for [snapshot] in the language of [s]. The goal and the
  /// VoiceOver line carry the snapshot's figures, so they are written
  /// together with it.
  factory CalorieWidgetLabels.of(S s, CalorieWidgetSnapshot snapshot) =>
      CalorieWidgetLabels.forFigures(
        s,
        consumedKcal: snapshot.consumedKcal,
        goalKcal: snapshot.goalKcal,
      );

  /// The labels for figures already stored, for when only the language
  /// changed.
  factory CalorieWidgetLabels.forFigures(
    S s, {
    required int consumedKcal,
    required int goalKcal,
  }) {
    final consumed = '$consumedKcal';
    final goal = '$goalKcal';
    return CalorieWidgetLabels(
      title: s.trendsCaloriesLabel,
      unit: s.kcalLabel,
      goal: s.calorieWidgetGoalLabel(goal),
      accessibility: s.calorieWidgetAccessibilityLabel(consumed, goal),
      openApp: s.calorieWidgetOpenAppHint,
      description: s.calorieWidgetDescription,
      kcalLeft: s.kcalLeftLabel,
      kcalOver: s.kcalTooMuchLabel,
      goalTitle: s.goalLabel,
      supplied: s.suppliedLabel,
      burned: s.burnedLabel,
      carbsShort: s.calorieWidgetCarbsShortLabel,
      fatShort: s.fatLabelShort.toUpperCase(),
      proteinShort: s.proteinLabelShort.toUpperCase(),
      gram: s.gramUnit,
      water: s.trendsWaterLabel,
      ml: s.mlLabel,
      breakfast: s.breakfastLabel,
      lunch: s.lunchLabel,
      dinner: s.dinnerLabel,
      snack: s.snackLabel,
      add: s.addLabel,
    );
  }

  /// The labels in the language the app is being read in.
  factory CalorieWidgetLabels.forAppLocale(CalorieWidgetSnapshot snapshot) =>
      CalorieWidgetLabels.of(appStrings(), snapshot);

  /// The strings for the language the app is being read in. Home publishes
  /// without a BuildContext, so this resolves [AppLocale] against the
  /// shipped locales the same way `main.dart` does for the reminder text;
  /// `lookupS` throws on a locale it does not know.
  static S appStrings() {
    final language = AppLocale.localeName.split(RegExp('[_-]')).first;
    final locale = basicLocaleListResolution([
      Locale(language),
    ], appLocales(S.supportedLocales));
    return lookupS(locale);
  }

  Map<String, String> languageJson() => {
    'title': title,
    'unit': unit,
    'openApp': openApp,
    'description': description,
    'kcalLeft': kcalLeft,
    'kcalOver': kcalOver,
    'goalTitle': goalTitle,
    'supplied': supplied,
    'burned': burned,
    'carbsShort': carbsShort,
    'fatShort': fatShort,
    'proteinShort': proteinShort,
    'gram': gram,
    'water': water,
    'ml': ml,
    'breakfast': breakfast,
    'lunch': lunch,
    'dinner': dinner,
    'snack': snack,
    'add': add,
  };

  Map<String, String> figureJson() => {
    'goal': goal,
    'accessibility': accessibility,
  };

  String encodeLanguage() => jsonEncode(languageJson());
}
