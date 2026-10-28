import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';

/// Fork-only: basal metabolic rate for the Polar kcal goal.
///
/// Upstream removed its `BMRCalc` (#993) once nothing there used a BMR any
/// more; the Polar goal (BMR + measured active energy + slider) still needs
/// one. Kept under its own name so it never collides with upstream again.
class PolarBmrCalc {
  ///
  /// Calculates BMR of UserEntity based on the 1990 Mifflin-St.Jeor equation
  /// from the paper 'A new predictive equation for resting energy
  /// expenditure in healthy individuals'
  /// by Mifflin & St.Jeor
  /// https://academic.oup.com/ajcn/article-abstract/51/2/241/4695104
  ///
  static double getBMRMifflinStJeor1990(UserEntity user) {
    return _dispatch(
      user,
      male: _mifflinStJeor1990Male,
      female: _mifflinStJeor1990Female,
    );
  }

  static double _mifflinStJeor1990Male(UserEntity user) {
    return 10 * user.weightKG + 6.25 * user.heightCM - 5 * user.age + 5;
  }

  static double _mifflinStJeor1990Female(UserEntity user) {
    return 10 * user.weightKG + 6.25 * user.heightCM - 5 * user.age - 161;
  }

  /// Non-binary users default to the mean of the male / female outputs unless
  /// they have explicitly opted into the estrogen-typical or testosterone-
  /// typical reference via [CaloriesProfileEntity].
  static double _dispatch(
    UserEntity user, {
    required double Function(UserEntity) male,
    required double Function(UserEntity) female,
  }) {
    switch (user.gender) {
      case UserGenderEntity.male:
        return male(user);
      case UserGenderEntity.female:
        return female(user);
      case UserGenderEntity.nonBinary:
        switch (user.caloriesProfile ?? CaloriesProfileEntity.averaged) {
          case CaloriesProfileEntity.averaged:
            return (male(user) + female(user)) / 2;
          case CaloriesProfileEntity.estrogenTypical:
            return female(user);
          case CaloriesProfileEntity.testosteroneTypical:
            return male(user);
        }
    }
  }
}
