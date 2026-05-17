import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/domain/entity/intake_entity.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';

class PolarInfluxdbDataSource {
  static const _keyUrl = 'polar_influxdb_url';
  static const _keyDatabase = 'polar_influxdb_database';
  static const _keyIsV2 = 'polar_influxdb_is_v2';
  static const _keyToken = 'polar_influxdb_token';
  static const _keyTriggerUrl = 'polar_influxdb_trigger_url';
  static const _keyProteinGPerKg = 'polar_protein_g_per_kg';
  static const double _defaultProteinGPerKg = 2.2;
  static const _keyFatGPerKg = 'polar_fat_g_per_kg';
  static const double _defaultFatGPerKg = 0.8;

  final _log = Logger('PolarInfluxdbDataSource');
  final FlutterSecureStorage _storage =
      SecureAppStorageProvider.secureAppStorage;

  Future<String> getUrl() async => await _storage.read(key: _keyUrl) ?? '';
  Future<String> getDatabase() async =>
      await _storage.read(key: _keyDatabase) ?? '';
  Future<bool> getIsV2() async =>
      (await _storage.read(key: _keyIsV2)) == 'true';
  Future<String> getToken() async => await _storage.read(key: _keyToken) ?? '';
  Future<String> getTriggerUrl() async =>
      await _storage.read(key: _keyTriggerUrl) ?? '';
  Future<bool> isPolarConfigured() async => (await getUrl()).isNotEmpty;
  Future<double> getProteinGPerKg() async {
    final raw = await _storage.read(key: _keyProteinGPerKg);
    return double.tryParse(raw ?? '') ?? _defaultProteinGPerKg;
  }

  Future<void> saveProteinGPerKg(double value) async {
    await _storage.write(key: _keyProteinGPerKg, value: value.toString());
  }

  Future<double> getFatGPerKg() async {
    final raw = await _storage.read(key: _keyFatGPerKg);
    return double.tryParse(raw ?? '') ?? _defaultFatGPerKg;
  }

  Future<void> saveFatGPerKg(double value) async {
    await _storage.write(key: _keyFatGPerKg, value: value.toString());
  }

  Future<void> saveConfig({
    required String url,
    required String database,
    required bool isV2,
    required String token,
    required String triggerUrl,
  }) async {
    await _storage.write(key: _keyUrl, value: url);
    await _storage.write(key: _keyDatabase, value: database);
    await _storage.write(key: _keyIsV2, value: isV2.toString());
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyTriggerUrl, value: triggerUrl);
  }

  /// Calls the configured trigger URL to start a fresh Polar → InfluxDB sync.
  /// Returns true if the server responded with HTTP 2xx.
  Future<bool> triggerSync() async {
    final triggerUrl = await getTriggerUrl();
    if (triggerUrl.isEmpty) return false;
    try {
      final response = await http
          .get(Uri.parse(triggerUrl))
          .timeout(const Duration(seconds: 30));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _log.warning('triggerSync failed: $e');
      return false;
    }
  }

  /// Writes a food intake entry to InfluxDB (measurement: `nutrition`).
  /// Fire-and-forget: call without await. Silently skipped if not configured.
  Future<void> writeIntake(IntakeEntity intake) async {
    if (!await isPolarConfigured()) return;
    try {
      final line = _buildIntakeLine(intake);
      await _writeLine(line);
    } catch (e) {
      _log.warning('writeIntake failed: $e');
    }
  }

  /// Deletes the InfluxDB nutrition point with the given timestamp.
  /// Fire-and-forget: call without await. Silently skipped if not configured.
  Future<void> deleteIntakeByTime(DateTime dateTime) async {
    if (!await isPolarConfigured()) return;
    final ns = dateTime.microsecondsSinceEpoch * 1000;
    final q = 'DELETE FROM nutrition WHERE time = $ns';
    try {
      await _executeQuery(q);
    } catch (e) {
      _log.warning('deleteIntakeByTime failed: $e');
    }
  }

  String _buildIntakeLine(IntakeEntity intake) {
    final meal = _escapeTag(intake.type.name);
    final food = _escapeTag(intake.meal.name ?? 'unknown');
    final n = intake.meal.nutriments;

    final fields = StringBuffer()
      ..write('kcal=${intake.totalKcal}')
      ..write(',carbs_g=${intake.totalCarbsGram}')
      ..write(',fats_g=${intake.totalFatsGram}')
      ..write(',proteins_g=${intake.totalProteinsGram}')
      ..write(',amount=${intake.amount}');

    final sugar = n.sugars100;
    if (sugar != null) fields.write(',sugar_g=${intake.amount * sugar / 100}');
    final fiber = n.fiber100;
    if (fiber != null) fields.write(',fiber_g=${intake.amount * fiber / 100}');
    final sodium = n.sodium100;
    if (sodium != null) {
      fields.write(',sodium=${intake.amount * sodium / 100}');
    }

    final ns = intake.dateTime.microsecondsSinceEpoch * 1000;
    return 'nutrition,meal=$meal,food=$food $fields $ns';
  }

  String _escapeTag(String value) => value
      .replaceAll(',', '\\,')
      .replaceAll('=', '\\=')
      .replaceAll(' ', '\\ ');

  Future<void> _writeLine(String line) async {
    final url = await getUrl();
    final database = await getDatabase();
    if (url.isEmpty || database.isEmpty) return;

    final isV2 = await getIsV2();
    final token = await getToken();
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final uri = Uri.parse('$baseUrl/write')
        .replace(queryParameters: {'db': database});
    final request = http.Request('POST', uri)..body = line;
    if (isV2 && token.isNotEmpty) {
      request.headers['Authorization'] = 'Token $token';
    }
    final streamed =
        await http.Client().send(request).timeout(const Duration(seconds: 10));
    if (streamed.statusCode >= 300) {
      _log.warning('InfluxDB write HTTP ${streamed.statusCode}');
    }
  }

  Future<void> _executeQuery(String q) async {
    final url = await getUrl();
    final database = await getDatabase();
    if (url.isEmpty || database.isEmpty) return;

    final isV2 = await getIsV2();
    final token = await getToken();
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final uri = Uri.parse('$baseUrl/query')
        .replace(queryParameters: {'db': database, 'q': q});
    final request = http.Request('GET', uri);
    if (isV2 && token.isNotEmpty) {
      request.headers['Authorization'] = 'Token $token';
    }
    await http.Client().send(request).timeout(const Duration(seconds: 10));
  }

  Future<double?> fetchLatestWeightKg() async {
    final url = await getUrl();
    final database = await getDatabase();
    if (url.isEmpty || database.isEmpty) return null;

    final isV2 = await getIsV2();
    final token = await getToken();
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    const q = 'SELECT last(weight) FROM koerpergewicht';
    try {
      final uri = Uri.parse('$baseUrl/query').replace(
        queryParameters: {'db': database, 'q': q},
      );
      final request = http.Request('GET', uri);
      if (isV2 && token.isNotEmpty) {
        request.headers['Authorization'] = 'Token $token';
      }
      final streamed = await http.Client()
          .send(request)
          .timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final series =
          (json['results'] as List?)?.firstOrNull?['series'] as List?;
      if (series == null || series.isEmpty) return null;

      final values = series[0]['values'] as List?;
      if (values == null || values.isEmpty) return null;

      return (values[0][1] as num?)?.toDouble();
    } catch (e) {
      _log.warning('Failed to fetch weight from InfluxDB: $e');
      return null;
    }
  }

  Future<double?> fetchActiveKcalForDate(DateTime date) async {
    final url = await getUrl();
    final database = await getDatabase();
    if (url.isEmpty || database.isEmpty) return null;

    final isV2 = await getIsV2();
    final token = await getToken();

    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    final start = DateTime(date.year, date.month, date.day).toUtc();
    final stop = start.add(const Duration(days: 1));

    // Use InfluxQL via the v1 compatibility endpoint (works for both v1 and v2)
    final q =
        "SELECT last(active_calories) FROM polar_activity WHERE time >= '${start.toIso8601String()}' AND time < '${stop.toIso8601String()}'";
    try {
      final uri = Uri.parse('$baseUrl/query').replace(
        queryParameters: {'db': database, 'q': q},
      );
      final request = http.Request('GET', uri);
      if (isV2 && token.isNotEmpty) {
        request.headers['Authorization'] = 'Token $token';
      }
      final streamedResponse =
          await http.Client().send(request).timeout(const Duration(seconds: 10));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode != 200) {
        _log.warning('InfluxDB query HTTP ${response.statusCode}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final series =
          (json['results'] as List?)?.firstOrNull?['series'] as List?;
      if (series == null || series.isEmpty) return null;

      final values = series[0]['values'] as List?;
      if (values == null || values.isEmpty) return null;

      // columns: ['time', 'last'] — value is at index 1
      return (values[0][1] as num?)?.toDouble();
    } catch (e) {
      _log.warning('Failed to fetch Polar InfluxDB data: $e');
      return null;
    }
  }
}
