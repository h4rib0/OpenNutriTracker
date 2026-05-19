/// A single nutrient value in an SFCD food detail response.
class SfcdNutrientDto {
  final String componentCode;
  final double? value;
  final String unitCode;

  const SfcdNutrientDto({
    required this.componentCode,
    required this.value,
    required this.unitCode,
  });

  factory SfcdNutrientDto.fromJson(Map<String, dynamic> json) {
    final component = json['component'] as Map<String, dynamic>?;
    final unit = json['unit'] as Map<String, dynamic>?;
    final rawValue = json['value'];
    return SfcdNutrientDto(
      componentCode: (component?['code'] as String?) ?? '',
      value: rawValue == null ? null : (rawValue as num).toDouble(),
      unitCode: (unit?['code'] as String?) ?? '',
    );
  }
}

/// Full food record returned by `GET /food/{id}?lang={lang}`.
class SfcdFoodDetailDto {
  final int id;
  final String name;
  final List<SfcdNutrientDto> values;

  const SfcdFoodDetailDto({
    required this.id,
    required this.name,
    required this.values,
  });

  factory SfcdFoodDetailDto.fromJson(Map<String, dynamic> json) {
    final rawValues = json['values'] as List<dynamic>? ?? [];
    return SfcdFoodDetailDto(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
      values: rawValues
          .whereType<Map<String, dynamic>>()
          .map(SfcdNutrientDto.fromJson)
          .toList(),
    );
  }

  double? nutrientValue(String componentCode) {
    for (final n in values) {
      if (n.componentCode == componentCode) return n.value;
    }
    return null;
  }
}
