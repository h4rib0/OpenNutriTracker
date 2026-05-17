import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';

class AddIntakeUsecase {
  final IntakeRepository _intakeRepository;
  final PolarInfluxdbDataSource _polarDataSource;

  AddIntakeUsecase(this._intakeRepository, this._polarDataSource);

  Future<void> addIntake(IntakeEntity intakeEntity) async {
    await _intakeRepository.addIntake(intakeEntity);
    _polarDataSource.writeIntake(intakeEntity); // fire-and-forget
  }
}
