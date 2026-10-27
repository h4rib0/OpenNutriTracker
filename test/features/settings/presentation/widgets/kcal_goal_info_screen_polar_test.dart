import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opennutritracker/core/domain/entity/kcal_goal_breakdown_entity.dart';
import 'package:opennutritracker/core/domain/usecase/get_fork_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/domain/usecase/get_kcal_goal_breakdown_usecase.dart';
import 'package:opennutritracker/core/utils/energy_unit_provider.dart';
import 'package:opennutritracker/features/settings/presentation/widgets/kcal_goal_info_screen.dart';
import 'package:opennutritracker/generated/l10n.dart';
import 'package:provider/provider.dart';

import '../../../../fixture/user_entity_fixtures.dart';

/// Fork: with Polar configured the transparency screen explains the Polar
/// formula and the body-weight macros instead of upstream's IOM path.
class _FakeBreakdownUsecase extends Fake
    implements GetKcalGoalBreakdownUsecase {
  final KcalGoalBreakdownEntity breakdown;

  _FakeBreakdownUsecase(this.breakdown);

  @override
  Future<KcalGoalBreakdownEntity> getBreakdown() async => breakdown;
}

class _FakeForkUsecase extends Fake implements GetForkGoalBreakdownUsecase {
  final ForkGoalBreakdown fork;

  _FakeForkUsecase(this.fork);

  @override
  Future<ForkGoalBreakdown> getBreakdown(
    KcalGoalBreakdownEntity upstream,
  ) async => fork;
}

Future<void> _pump(WidgetTester tester, ForkGoalBreakdown fork) async {
  final breakdown = KcalGoalBreakdownEntity.compute(
    user: UserEntityFixtures.youngSedentaryMaleWantingToMaintainWeight,
    totalKcalActivities: 200,
  );
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => EnergyUnitProvider(usesKilojoules: false),
      child: MaterialApp(
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.supportedLocales,
        home: KcalGoalInfoScreen(
          usecase: _FakeBreakdownUsecase(breakdown),
          forkUsecase: _FakeForkUsecase(fork),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const polar = PolarKcalBreakdown(
    weightKg: 78,
    weightFromInflux: true,
    bmrKcal: 1800,
    polarActiveKcal: 650,
    activityKcal: 200,
    manualKcalAdjustment: -500,
  );
  const macros = BodyWeightMacroBreakdown(
    totalKcalGoal: 2150,
    weightKg: 78,
    proteinGPerKg: 2.2,
    fatGPerKg: 0.8,
    proteinsGrams: 171.6,
    fatsGrams: 62.4,
    carbsGrams: 194.2,
  );

  testWidgets('Polar active: shows the Polar formula and its total', (
    tester,
  ) async {
    await _pump(
      tester,
      const ForkGoalBreakdown(polar: polar, bodyWeightMacros: macros),
    );

    expect(
      find.text('Polar: Grundumsatz + gemessene Aktivität'),
      findsOneWidget,
    );
    expect(find.text('Gewicht (InfluxDB)'), findsOneWidget);
    // 1800 + 650 + 200 - 500
    expect(polar.totalKcalGoal, 2150);
    await tester.scrollUntilVisible(find.textContaining('2150'), 200);
    expect(find.textContaining('2150'), findsWidgets);
  });

  testWidgets('body-weight macros: explains g/kg instead of the % split', (
    tester,
  ) async {
    await _pump(
      tester,
      const ForkGoalBreakdown(polar: polar, bodyWeightMacros: macros),
    );

    final line = find.textContaining('2.2 g × 78.0 kg = 171 g');
    await tester.scrollUntilVisible(line, 200);
    expect(line, findsOneWidget);
  });

  testWidgets(
    'without Polar or body-weight macros the upstream screen renders',
    (tester) async {
      await _pump(tester, ForkGoalBreakdown.none);

      expect(
        find.text('Polar: Grundumsatz + gemessene Aktivität'),
        findsNothing,
      );
    },
  );
}
