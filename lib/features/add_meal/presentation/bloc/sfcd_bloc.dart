import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/usecase/get_config_usecase.dart';
import 'package:opennutritracker/features/add_meal/domain/entity/meal_entity.dart';
import 'package:opennutritracker/features/add_meal/domain/usecase/search_products_usecase.dart';

part 'sfcd_event.dart';
part 'sfcd_state.dart';

class SfcdBloc extends Bloc<SfcdEvent, SfcdState> {
  final _log = Logger('SfcdBloc');

  final SearchProductsUseCase _searchProductsUseCase;
  final GetConfigUsecase _getConfigUsecase;

  String _searchString = '';

  SfcdBloc(this._searchProductsUseCase, this._getConfigUsecase)
      : super(SfcdInitial()) {
    on<LoadSfcdEvent>((event, emit) async {
      if (event.searchString != _searchString) {
        _searchString = event.searchString;
        emit(SfcdLoadingState());
        try {
          final result = await _searchProductsUseCase.searchSfcdFoodByString(
            _searchString,
          );
          final config = await _getConfigUsecase.getConfig();
          emit(SfcdLoadedState(
            food: result.meals,
            usesImperialUnits: config.usesImperialUnits,
            remoteSourceEmpty: result.remoteSourceEmpty,
          ));
        } catch (error) {
          _log.severe(error);
          emit(SfcdFailedState());
        }
      }
    });
    on<RefreshSfcdEvent>((event, emit) async {
      emit(SfcdLoadingState());
      try {
        final result = await _searchProductsUseCase.searchSfcdFoodByString(
          _searchString,
        );
        emit(SfcdLoadedState(
          food: result.meals,
          remoteSourceEmpty: result.remoteSourceEmpty,
        ));
      } catch (error) {
        _log.severe(error);
        emit(SfcdFailedState());
      }
    });
  }
}
