import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:logging/logging.dart';
import 'package:opennutritracker/core/utils/secure_app_storage_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fork-only: the recovery code that re-attaches the Supabase backup
/// (custom meals, recipes, nutrient overrides) to a new install.
///
/// Sync uses anonymous auth, so a reinstall gets a new `auth.uid()` and
/// row-level security hides the old rows. The code is registered per user
/// via the `set_recovery_code` RPC; `claim_recovery_code` from another user
/// moves the old rows over. See `docs/supabase-sync/user_recovery_codes.sql`.
class SupabaseRecoveryDataSource {
  static const _keyCode = 'supabase_recovery_code';

  /// The Supabase user the stored code is registered for.
  static const _keyRegisteredFor = 'supabase_recovery_registered_for';

  /// Crockford base32: no I, L, O or U, so the code survives being read
  /// aloud or typed from paper.
  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _length = 20; // 100 bits
  static const _groupSize = 4;

  final _log = Logger('SupabaseRecoveryDataSource');
  final SupabaseClient _client;
  final FlutterSecureStorage _storage;

  SupabaseRecoveryDataSource(this._client, [FlutterSecureStorage? storage])
    : _storage = storage ?? SecureAppStorageProvider.secureAppStorage;

  /// A fresh random code, formatted as `XXXX-XXXX-XXXX-XXXX-XXXX`.
  static String generate([Random? random]) {
    final rng = random ?? Random.secure();
    final raw = List.generate(
      _length,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
    return format(raw);
  }

  /// The canonical form sent to the server: upper case, separators dropped,
  /// and the look-alikes Crockford folds (O → 0, I / L → 1) folded. Null
  /// when what is left is not a full code.
  static String? normalize(String input) {
    final folded = input
        .toUpperCase()
        .replaceAll(RegExp(r'[\s\-_]'), '')
        .replaceAll('O', '0')
        .replaceAll(RegExp('[IL]'), '1');
    if (folded.length != _length) return null;
    if (folded.split('').any((c) => !_alphabet.contains(c))) return null;
    return folded;
  }

  /// [code] in groups of four, for display.
  static String format(String code) {
    final raw = normalize(code) ?? code;
    final groups = <String>[];
    for (var i = 0; i < raw.length; i += _groupSize) {
      groups.add(raw.substring(i, min(i + _groupSize, raw.length)));
    }
    return groups.join('-');
  }

  String? get _userId => _client.auth.currentUser?.id;

  /// The code registered for the current Supabase user, or null when there
  /// is none yet (or it was registered by an earlier install).
  Future<String?> getRegisteredCode() async {
    final userId = _userId;
    if (userId == null) return null;
    final code = await _storage.read(key: _keyCode);
    final registeredFor = await _storage.read(key: _keyRegisteredFor);
    if (code == null || registeredFor != userId) return null;
    return format(code);
  }

  /// Makes sure the current user has a registered code and returns it, or
  /// null when not signed in or the server could not be reached.
  ///
  /// A code left in storage by an earlier user (Android may restore the
  /// app's storage after a reinstall) is claimed rather than replaced, so
  /// the backup follows it.
  Future<String?> ensureRegistered() async {
    final registered = await getRegisteredCode();
    if (registered != null) return registered;
    final userId = _userId;
    if (userId == null) return null;

    try {
      final stored = await _storage.read(key: _keyCode);
      final storedNormalized = stored == null ? null : normalize(stored);
      if (storedNormalized != null) {
        final moved = await _claimRpc(storedNormalized);
        if (moved >= 0) {
          await _remember(storedNormalized, userId);
          return format(storedNormalized);
        }
      }
      final code = normalize(generate())!;
      await _client.rpc('set_recovery_code', params: {'code': code});
      await _remember(code, userId);
      return format(code);
    } catch (e) {
      _log.warning('Could not register the recovery code: $e');
      return null;
    }
  }

  /// Claims [input] for the current user. Returns the number of rows moved
  /// (0 when the code is already this user's), or null when no user has
  /// registered it. Throws [FormatException] for input that is not a code
  /// and [StateError] when not signed in; network errors propagate.
  Future<int?> claim(String input) async {
    final code = normalize(input);
    if (code == null) {
      throw const FormatException('Not a recovery code');
    }
    final userId = _userId;
    if (userId == null) throw StateError('Not signed in to Supabase');
    final moved = await _claimRpc(code);
    if (moved < 0) return null;
    await _remember(code, userId);
    return moved;
  }

  Future<int> _claimRpc(String code) async {
    final result = await _client.rpc(
      'claim_recovery_code',
      params: {'code': code},
    );
    return (result as num).toInt();
  }

  Future<void> _remember(String code, String userId) async {
    await _storage.write(key: _keyCode, value: code);
    await _storage.write(key: _keyRegisteredFor, value: userId);
  }
}
