import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';

/// In-memory stand-in for the secure storage; only read / write / delete.
class _MemoryStorage implements FlutterSecureStorage {
  final values = <String, String>{};

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    switch (invocation.memberName) {
      case #read:
        return Future<String?>.value(values[key]);
      case #write:
        final value = invocation.namedArguments[#value] as String?;
        value == null ? values.remove(key) : values[key!] = value;
        return Future<void>.value();
      case #delete:
        values.remove(key);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

String _series(num value) => jsonEncode({
  'results': [
    {
      'series': [
        {
          'columns': ['time', 'last'],
          'values': [
            ['2026-10-28T00:00:00Z', value],
          ],
        },
      ],
    },
  ],
});

final _noData = jsonEncode({
  'results': [<String, dynamic>{}],
});

/// Fork: the Polar reads a home load makes are answered once, and a bad
/// connection falls back to the last good value instead of leaving the
/// screen waiting on one timeout per caller.
void main() {
  late _MemoryStorage storage;
  late List<String> queries;
  late http.Response Function(String q) respond;
  late bool offline;

  PolarInfluxdbDataSource polar() => PolarInfluxdbDataSource(
    storage: storage,
    httpClient: MockClient((request) async {
      final q = request.url.queryParameters['q'] ?? request.url.toString();
      queries.add(q);
      if (offline) throw http.ClientException('offline');
      return respond(q);
    }),
  );

  setUp(() {
    storage = _MemoryStorage()
      ..values.addAll({
        'polar_influxdb_url': 'http://influx.invalid',
        'polar_influxdb_database': 'polar',
      });
    queries = [];
    offline = false;
    respond = (q) => http.Response(
      q.contains('koerpergewicht') ? _series(65.4) : _series(420),
      200,
    );
  });

  test('concurrent callers share one weight query', () async {
    final ds = polar();
    final results = await Future.wait([
      ds.fetchLatestWeightKg(),
      ds.fetchLatestWeightKg(),
      ds.fetchLatestWeightKg(),
    ]);
    expect(results, [65.4, 65.4, 65.4]);
    expect(queries.where((q) => q.contains('koerpergewicht')), hasLength(1));
  });

  test('a failed query is shared too, so it costs one timeout', () async {
    offline = true;
    final ds = polar();
    await ds.fetchLatestWeightKg();
    await ds.fetchLatestWeightKg();
    await ds.fetchActiveKcalForDate(DateTime(2026, 10, 28, 9));
    await ds.fetchActiveKcalForDate(DateTime(2026, 10, 28, 14));
    expect(queries, hasLength(2));
  });

  test('offline falls back to the last weight seen', () async {
    final ds = polar();
    expect(await ds.fetchLatestWeightKg(), 65.4);

    offline = true;
    ds.clearCache();
    expect(await ds.fetchLatestWeightKg(), 65.4);
  });

  test('offline falls back to the active kcal of the same day only', () async {
    final ds = polar();
    final today = DateTime(2026, 10, 28, 12);
    expect(await ds.fetchActiveKcalForDate(today), 420);

    offline = true;
    ds.clearCache();
    expect(await ds.fetchActiveKcalForDate(today), 420);
    expect(await ds.fetchActiveKcalForDate(DateTime(2026, 10, 29)), isNull);
  });

  test('no data yet is null, not the last value', () async {
    final ds = polar();
    final today = DateTime(2026, 10, 28);
    expect(await ds.fetchActiveKcalForDate(today), 420);

    respond = (_) => http.Response(_noData, 200);
    ds.clearCache();
    expect(await ds.fetchActiveKcalForDate(today), isNull);
  });

  test('a server error counts as unreachable', () async {
    final ds = polar();
    expect(await ds.fetchLatestWeightKg(), 65.4);

    respond = (_) => http.Response('gateway timeout', 504);
    ds.clearCache();
    expect(await ds.fetchLatestWeightKg(), 65.4);
  });

  test('a manual sync clears the cache for the reload after it', () async {
    storage.values['polar_influxdb_trigger_url'] = 'http://sync.invalid/run';
    final ds = polar();
    expect(await ds.fetchLatestWeightKg(), 65.4);

    respond = (q) =>
        http.Response(q.contains('koerpergewicht') ? _series(64.9) : '', 200);
    await ds.triggerSync();
    expect(await ds.fetchLatestWeightKg(), 64.9);
  });

  test('another server drops the last values of the old one', () async {
    final ds = polar();
    expect(await ds.fetchLatestWeightKg(), 65.4);

    await ds.saveConfig(
      url: 'http://other.invalid',
      database: 'polar',
      isV2: false,
      token: '',
      triggerUrl: '',
    );
    offline = true;
    expect(await ds.fetchLatestWeightKg(), isNull);
  });
}
