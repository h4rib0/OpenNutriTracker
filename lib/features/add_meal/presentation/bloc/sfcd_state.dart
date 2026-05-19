part of 'sfcd_bloc.dart';

abstract class SfcdState extends Equatable {
  const SfcdState();
}

class SfcdInitial extends SfcdState {
  @override
  List<Object?> get props => [];
}

class SfcdLoadingState extends SfcdState {
  @override
  List<Object?> get props => [];
}

class SfcdLoadedState extends SfcdState {
  final List<MealEntity> food;
  final bool usesImperialUnits;
  final bool remoteSourceEmpty;

  const SfcdLoadedState({
    required this.food,
    this.usesImperialUnits = false,
    required this.remoteSourceEmpty,
  });

  @override
  List<Object?> get props => [food, usesImperialUnits, remoteSourceEmpty];
}

class SfcdFailedState extends SfcdState {
  @override
  List<Object?> get props => [];
}
