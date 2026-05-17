part of 'profile_bloc.dart';

abstract class ProfileState extends Equatable {
  const ProfileState();
}

class ProfileInitial extends ProfileState {
  @override
  List<Object> get props => [];
}

class ProfileLoadingState extends ProfileState {
  @override
  List<Object?> get props => [];
}

class ProfileLoadedState extends ProfileState {
  final UserBMIEntity userBMI;
  final UserEntity userEntity;
  final bool usesImperialUnits;
  final bool isPolarActive;
  final double? influxWeightKg;

  const ProfileLoadedState({
    required this.userBMI,
    required this.userEntity,
    required this.usesImperialUnits,
    this.isPolarActive = false,
    this.influxWeightKg,
  });

  @override
  List<Object?> get props => [userBMI, userEntity, usesImperialUnits, isPolarActive, influxWeightKg];
}
