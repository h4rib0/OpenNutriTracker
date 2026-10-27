import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/supported_language.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sfcd/sfcd_const.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sfcd/sfcd_food_detail_dto.dart';
import 'package:opennutritracker/features/add_meal/data/dto/sfcd/sfcd_food_dto.dart';

class SfcdDataSource {
  static const _timeout = Duration(seconds: 10);

  final _log = Logger('SfcdDataSource');

  String _langCode() {
    final lang = SupportedLanguage.fromCode(Platform.localeName);
    switch (lang) {
      case SupportedLanguage.de:
        return 'de';
      case SupportedLanguage.it:
        return 'it';
      default:
        return 'en';
    }
  }

  Uri _buildUri(String path, Map<String, String> params) {
    final base =
        SfcdConst.baseUrl.endsWith('/') ? SfcdConst.baseUrl : '${SfcdConst.baseUrl}/';
    return Uri.parse('$base$path').replace(queryParameters: params);
  }

  Future<List<SfcdFoodDto>> search(String searchString) async {
    final term = searchString.trim();

    // German plurals often end in 'n' (Kartoffeln, Erdbeeren, Tomaten).
    // The API matches substrings, so "Kartoffeln" misses "Kartoffel*" entries.
    // Run both the original term and the stem (without trailing 'n') in
    // parallel and merge, capped at searchLimit unique results.
    final futures = [_searchRaw(term)];
    if (term.length > 3 && term.toLowerCase().endsWith('n')) {
      futures.add(_searchRaw(term.substring(0, term.length - 1)));
    }

    final results = await Future.wait(futures);
    final seen = <int>{};
    return results
        .expand((list) => list)
        .where((f) => seen.add(f.id))
        .take(SfcdConst.searchLimit)
        .toList();
  }

  Future<List<SfcdFoodDto>> _searchRaw(String term) async {
    final uri = _buildUri('foods', {
      'search': term,
      'lang': _langCode(),
      'limit': SfcdConst.searchLimit.toString(),
    });
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) {
        _log.warning('SFCD search HTTP ${response.statusCode}');
        return [];
      }
      final body = jsonDecode(response.body);
      if (body is List) {
        return body
            .whereType<Map<String, dynamic>>()
            .map(SfcdFoodDto.fromJson)
            .toList();
      }
      return [];
    } catch (e) {
      _log.warning('SFCD search "$term" failed: $e');
      return [];
    }
  }

  Future<SfcdFoodDetailDto?> fetchDetail(int foodId) async {
    final uri = _buildUri('food/$foodId', {'lang': _langCode()});
    try {
      final response = await http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>?;
      if (body == null) return null;
      return SfcdFoodDetailDto.fromJson(body);
    } catch (e) {
      _log.warning('SFCD fetchDetail $foodId failed: $e');
      return null;
    }
  }

  /// Searches and fetches detail data for all results in parallel.
  /// Returns at most [SfcdConst.searchLimit] fully-populated food details.
  Future<List<SfcdFoodDetailDto>> searchWithDetails(
    String searchString,
  ) async {
    final foods = await search(searchString);
    if (foods.isEmpty) return [];

    final details = await Future.wait(
      foods.map((f) => fetchDetail(f.id)),
    );

    return details.whereType<SfcdFoodDetailDto>().toList();
  }
}
