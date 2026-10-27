import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';

class DeleteIntakeUsecase {
  final IntakeRepository _intakeRepository;
  final PolarInfluxdbDataSource _polarDataSource;

  DeleteIntakeUsecase(this._intakeRepository, this._polarDataSource);

  Future<void> deleteIntake(IntakeEntity intakeEntity) async {
    await _intakeRepository.deleteIntake(intakeEntity);
    _polarDataSource.deleteIntakeByTime(intakeEntity.dateTime); // fire-and-forget
  }
}
