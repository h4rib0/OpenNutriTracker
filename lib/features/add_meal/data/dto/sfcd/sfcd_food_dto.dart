/// A single food item returned by the SFCD search endpoint.
class SfcdFoodDto {
  final int id;
  final String name;

  const SfcdFoodDto({required this.id, required this.name});

  factory SfcdFoodDto.fromJson(Map<String, dynamic> json) {
    return SfcdFoodDto(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? '',
    );
  }
}
