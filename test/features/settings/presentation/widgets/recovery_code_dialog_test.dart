import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/usecase/supabase_backup_usecase.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/recovery_code_dialog.dart';
import 'package:opennutritracker/generated/l10n.dart';

class _FakeBackup implements SupabaseBackupUsecase {
  _FakeBackup(this.code, {this.claimResult});

  String? code;
  final int? claimResult;
  final claimed = <String>[];

  @override
  Future<String?> getRecoveryCode() async => code;

  @override
  Future<String?> getRegisteredRecoveryCode() async => code;

  @override
  Future<int?> restoreWithCode(String input) async {
    claimed.add(input);
    if (claimResult != null) code = input;
    return claimResult;
  }

  @override
  Future<void> initOnStartup() async {}

  @override
  Future<void> pull() async {}
}

Future<void> _pump(WidgetTester tester, SupabaseBackupUsecase backup) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        S.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: S.supportedLocales,
      home: Scaffold(body: RecoveryCodeDialog(backupUsecase: backup)),
    ),
  );
  await tester.pumpAndSettle();
}

/// Fork: Settings -> Polar & Sync -> Wiederherstellungscode.
void main() {
  testWidgets('shows the install\'s code', (tester) async {
    await _pump(tester, _FakeBackup('ABCD-EFGH-JKMN-PQRS-TVWX'));
    expect(find.text('ABCD-EFGH-JKMN-PQRS-TVWX'), findsOneWidget);
  });

  testWidgets('says so when offline', (tester) async {
    await _pump(tester, _FakeBackup(null));
    expect(find.textContaining('keine Verbindung'), findsOneWidget);
  });

  testWidgets('claims an entered code and shows what came back', (
    tester,
  ) async {
    final backup = _FakeBackup('AAAA-AAAA-AAAA-AAAA-AAAA', claimResult: 12);
    await _pump(tester, backup);

    await tester.enterText(find.byType(TextField), 'BBBB-BBBB-BBBB-BBBB-BBBB');
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();

    expect(backup.claimed, ['BBBB-BBBB-BBBB-BBBB-BBBB']);
    expect(find.textContaining('12 Einträge übernommen'), findsOneWidget);
    expect(find.text('BBBB-BBBB-BBBB-BBBB-BBBB'), findsOneWidget);
  });

  testWidgets('one row reads in the singular', (tester) async {
    final backup = _FakeBackup('AAAA-AAAA-AAAA-AAAA-AAAA', claimResult: 1);
    await _pump(tester, backup);

    await tester.enterText(find.byType(TextField), 'BBBB-BBBB-BBBB-BBBB-BBBB');
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('1 Eintrag übernommen'), findsOneWidget);
  });

  testWidgets('an empty backup is not mistaken for the own code', (
    tester,
  ) async {
    final backup = _FakeBackup('AAAA-AAAA-AAAA-AAAA-AAAA', claimResult: 0);
    await _pump(tester, backup);

    await tester.enterText(find.byType(TextField), 'BBBB-BBBB-BBBB-BBBB-BBBB');
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('keine Einträge'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bbbb bbbb bbbb bbbb bbbb');
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('gehört bereits'), findsOneWidget);
  });

  testWidgets('an unknown code is reported', (tester) async {
    final backup = _FakeBackup('AAAA-AAAA-AAAA-AAAA-AAAA');
    await _pump(tester, backup);

    await tester.enterText(find.byType(TextField), 'BBBB-BBBB-BBBB-BBBB-BBBB');
    await tester.tap(find.text('Wiederherstellen'));
    await tester.pumpAndSettle();

    expect(find.textContaining('nicht bekannt'), findsOneWidget);
  });
}
