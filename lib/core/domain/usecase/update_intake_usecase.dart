import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/data/repository/intake_repository.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';

class UpdateIntakeUsecase {
  final IntakeRepository _intakeRepository;
  final PolarInfluxdbDataSource _polarDataSource;

  UpdateIntakeUsecase(this._intakeRepository, this._polarDataSource);

  Future<IntakeEntity?> updateIntake(
    String intakeId,
    Map<String, dynamic> intakeFields,
  ) async {
    final updated = await _intakeRepository.updateIntake(intakeId, intakeFields);
    if (updated != null) {
      _polarDataSource.writeIntake(updated); // fire-and-forget, overwrites by timestamp
    }
    return updated;
  }
}
