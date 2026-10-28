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

  // One home load asks for the weight and the active kcal from several
  // usecases. Each value is queried once and the answer — a failure too — is
  // kept briefly, so a bad connection costs one timeout, not one per caller.
  static const _cacheTtl = Duration(seconds: 30);
  static const _queryTimeout = Duration(seconds: 5);
  _CachedQuery? _weight;
  final _activeKcalByDay = <String, _CachedQuery>{};

  // The last good answers, for when InfluxDB cannot be reached: the weight
  // as `<kg>`, the active kcal as `<yyyy-mm-dd>|<kcal>` (only used that day).
  static const _keyLastWeightKg = 'polar_last_weight_kg';
  static const _keyLastActiveKcal = 'polar_last_active_kcal';

  final FlutterSecureStorage _storage;
  final http.Client _http;

  /// [httpClient] and [storage] are for tests.
  PolarInfluxdbDataSource({http.Client? httpClient, FlutterSecureStorage? storage})
    : _http = httpClient ?? http.Client(),
      _storage = storage ?? SecureAppStorageProvider.secureAppStorage;

  Future<String> getUrl() async => await _storage.read(key: _keyUrl) ?? '';
  Future<String> getDatabase() async => await _storage.read(key: _keyDatabase) ?? '';
  Future<bool> getIsV2() async => (await _storage.read(key: _keyIsV2)) == 'true';
  Future<String> getToken() async => await _storage.read(key: _keyToken) ?? '';
  Future<String> getTriggerUrl() async => await _storage.read(key: _keyTriggerUrl) ?? '';
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

  Future<void> saveConfig({required String url, required String database, required bool isV2, required String token, required String triggerUrl}) async {
    await _storage.write(key: _keyUrl, value: url);
    await _storage.write(key: _keyDatabase, value: database);
    await _storage.write(key: _keyIsV2, value: isV2.toString());
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyTriggerUrl, value: triggerUrl);
    // Another server's last values are not this one's.
    await _storage.delete(key: _keyLastWeightKg);
    await _storage.delete(key: _keyLastActiveKcal);
    clearCache();
  }

  /// Forgets the briefly cached answers, so the next read queries InfluxDB.
  void clearCache() {
    _weight = null;
    _activeKcalByDay.clear();
  }

  /// Calls the configured trigger URL to start a fresh Polar → InfluxDB sync.
  /// Returns true if the server responded with HTTP 2xx.
  Future<bool> triggerSync() async {
    final triggerUrl = await getTriggerUrl();
    if (triggerUrl.isEmpty) return false;
    try {
      final response = await _http.get(Uri.parse(triggerUrl)).timeout(const Duration(seconds: 30));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      _log.warning('triggerSync failed: $e');
      return false;
    } finally {
      // Whatever the sync brought in should show on the reload that follows.
      clearCache();
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

    final amount = intake.amount;
    void writeField(String key, double? per100) {
      if (per100 != null) fields.write(',$key=${amount * per100 / 100}');
    }

    writeField('sugar_g', n.sugars100);
    writeField('fiber_g', n.fiber100);
    writeField('sodium_g', n.sodium100);
    writeField('saturated_fat_g', n.saturatedFat100);
    writeField('potassium_g', n.potassium100);
    writeField('calcium_g', n.calcium100);
    writeField('iron_mg', n.iron100);
    writeField('magnesium_g', n.magnesium100);
    writeField('vitamin_d_ug', n.vitaminD100);
    writeField('vitamin_b12_ug', n.vitaminB12100);

    final ns = intake.dateTime.microsecondsSinceEpoch * 1000;
    return 'nutrition,meal=$meal,food=$food $fields $ns';
  }

  String _escapeTag(String value) => value.replaceAll(',', '\\,').replaceAll('=', '\\=').replaceAll(' ', '\\ ');

  Future<void> _writeLine(String line) async {
    final url = await getUrl();
    final database = await getDatabase();
    if (url.isEmpty || database.isEmpty) return;

    final isV2 = await getIsV2();
    final token = await getToken();
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    final uri = Uri.parse('$baseUrl/write').replace(queryParameters: {'db': database});
    final request = http.Request('POST', uri)..body = line;
    if (isV2 && token.isNotEmpty) {
      request.headers['Authorization'] = 'Token $token';
    }
    final streamed = await _http.send(request).timeout(const Duration(seconds: 10));
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

    final uri = Uri.parse('$baseUrl/query').replace(queryParameters: {'db': database, 'q': q});
    final request = http.Request('GET', uri);
    if (isV2 && token.isNotEmpty) {
      request.headers['Authorization'] = 'Token $token';
    }
    await _http.send(request).timeout(const Duration(seconds: 10));
  }

  /// The latest weight in InfluxDB (`koerpergewicht`), the last one seen
  /// when InfluxDB cannot be reached, or null when there is none.
  Future<double?> fetchLatestWeightKg() {
    final cached = _weight;
    if (cached != null && cached.isFresh) return cached.value;
    final value = _loadLatestWeightKg();
    _weight = _CachedQuery(value);
    return value;
  }

  Future<double?> _loadLatestWeightKg() async {
    final result = await _queryLast('SELECT last(weight) FROM koerpergewicht');
    if (!result.reached) {
      return double.tryParse(await _storage.read(key: _keyLastWeightKg) ?? '');
    }
    final weightKg = result.value;
    if (weightKg != null) {
      await _storage.write(key: _keyLastWeightKg, value: weightKg.toString());
    }
    return weightKg;
  }

  /// Fetches the total calories burned for [date] from the `polar_activity`
  /// measurement (field: `calories`). Returns null when Polar is not reachable.
  Future<double?> fetchTotalKcalForDate(DateTime date) async {
    final result = await _queryLast('SELECT last("calories") FROM "polar_activity" ${_dayRange(date)}');
    return result.value;
  }

  /// Polar's active energy for [date]. Null when InfluxDB has nothing for
  /// that day yet; when it cannot be reached, the last value seen for that
  /// day, if any.
  Future<double?> fetchActiveKcalForDate(DateTime date) {
    final day = _dayKey(date);
    final cached = _activeKcalByDay[day];
    if (cached != null && cached.isFresh) return cached.value;
    final value = _loadActiveKcal(date, day);
    _activeKcalByDay[day] = _CachedQuery(value);
    return value;
  }

  Future<double?> _loadActiveKcal(DateTime date, String day) async {
    final result = await _queryLast('SELECT last(active_calories) FROM polar_activity ${_dayRange(date)}');
    if (!result.reached) {
      final last = (await _storage.read(key: _keyLastActiveKcal))?.split('|');
      if (last == null || last.length != 2 || last[0] != day) return null;
      return double.tryParse(last[1]);
    }
    final kcal = result.value;
    if (kcal != null) {
      await _storage.write(key: _keyLastActiveKcal, value: '$day|$kcal');
    }
    return kcal;
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _dayRange(DateTime date) {
    final start = DateTime(date.year, date.month, date.day).toUtc();
    final stop = start.add(const Duration(days: 1));
    return "WHERE time >= '${start.toIso8601String()}' AND time < '${stop.toIso8601String()}'";
  }

  /// Runs an InfluxQL `SELECT last(...)` via the v1 compatibility endpoint
  /// (works for both v1 and v2). [reached] is false when InfluxDB could not
  /// be asked or did not answer; [value] is null when it had no data.
  Future<({bool reached, double? value})> _queryLast(String q) async {
    final url = await getUrl();
    final database = await getDatabase();
    if (url.isEmpty || database.isEmpty) return (reached: false, value: null);

    final isV2 = await getIsV2();
    final token = await getToken();
    final baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;

    try {
      final uri = Uri.parse('$baseUrl/query').replace(queryParameters: {'db': database, 'q': q});
      final request = http.Request('GET', uri);
      if (isV2 && token.isNotEmpty) {
        request.headers['Authorization'] = 'Token $token';
      }
      final streamed = await _http.send(request).timeout(_queryTimeout);
      final response = await http.Response.fromStream(streamed).timeout(_queryTimeout);

      if (response.statusCode != 200) {
        _log.warning('InfluxDB query HTTP ${response.statusCode}');
        return (reached: false, value: null);
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final series = (json['results'] as List?)?.firstOrNull?['series'] as List?;
      final values = (series == null || series.isEmpty) ? null : series[0]['values'] as List?;
      if (values == null || values.isEmpty) return (reached: true, value: null);

      // columns: ['time', 'last'] — value is at index 1
      return (reached: true, value: (values[0][1] as num?)?.toDouble());
    } catch (e) {
      _log.warning('InfluxDB query failed: $e');
      return (reached: false, value: null);
    }
  }
}

/// One query's answer, shared by every caller while it is fresh — including
/// callers that arrive while it is still in flight.
class _CachedQuery {
  _CachedQuery(this.value) : _at = DateTime.now();

  final Future<double?> value;
  final DateTime _at;

  bool get isFresh => DateTime.now().difference(_at) < PolarInfluxdbDataSource._cacheTtl;
}
