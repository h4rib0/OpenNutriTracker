import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/data/data_source/supabase_recovery_data_source.dart';

/// Fork: the shape of the Supabase recovery code.
void main() {
  test('generate gives five groups of four Crockford characters', () {
    for (var seed = 0; seed < 50; seed++) {
      final code = SupabaseRecoveryDataSource.generate(Random(seed));
      expect(
        code,
        matches(RegExp(r'^[0-9A-HJKMNP-TV-Z]{4}(-[0-9A-HJKMNP-TV-Z]{4}){4}$')),
      );
      expect(
        SupabaseRecoveryDataSource.normalize(code),
        code.replaceAll('-', ''),
      );
    }
  });

  test('normalize accepts what people type', () {
    expect(
      SupabaseRecoveryDataSource.normalize(' abcd efgh-jkmn_pqrs tvwx '),
      'ABCDEFGHJKMNPQRSTVWX',
    );
    // Crockford look-alikes fold to digits.
    expect(
      SupabaseRecoveryDataSource.normalize('O0IL-1111-2222-3333-4444'),
      '00111111222233334444',
    );
  });

  test('normalize rejects anything that is not a full code', () {
    expect(SupabaseRecoveryDataSource.normalize(''), isNull);
    expect(SupabaseRecoveryDataSource.normalize('ABCD-EFGH'), isNull);
    expect(
      SupabaseRecoveryDataSource.normalize('ABCD-EFGH-JKMN-PQRS-TVWXY'),
      isNull,
    );
    expect(
      SupabaseRecoveryDataSource.normalize('ABCD-EFGH-JKMN-PQRS-TVWU'),
      isNull,
    );
  });

  test('format groups a raw code in fours', () {
    expect(
      SupabaseRecoveryDataSource.format('abcdefghjkmnpqrstvwx'),
      'ABCD-EFGH-JKMN-PQRS-TVWX',
    );
  });
}
