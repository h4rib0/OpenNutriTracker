part of 'sfcd_bloc.dart';

abstract class SfcdEvent extends Equatable {
  const SfcdEvent();
}

class LoadSfcdEvent extends SfcdEvent {
  final String searchString;

  const LoadSfcdEvent({required this.searchString});

  @override
  List<Object?> get props => [searchString];
}

class RefreshSfcdEvent extends SfcdEvent {
  const RefreshSfcdEvent();

  @override
  List<Object?> get props => [];
}
