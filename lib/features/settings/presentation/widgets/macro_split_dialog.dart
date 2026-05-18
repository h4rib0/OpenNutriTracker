import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Three sliders that distribute the daily kcal goal across
/// carbohydrate, protein, and fat. Moving any one slider rebalances
/// the other two against 100% so the trio always adds up, with each
/// macro pinned to a 5% floor so the diary still has something to
/// track against if a user pulls one slider all the way down.
///
/// When Polar is configured the dialog switches to a body-weight mode
/// (g/kg) for protein and fat, with carbs filling the remaining kcal.
class MacroSplitDialog extends StatefulWidget {
  final SettingsBloc settingsBloc;
  final HomeBloc homeBloc;
  final DiaryBloc diaryBloc;
  final CalendarDayBloc calendarDayBloc;

  const MacroSplitDialog({
    super.key,
    required this.settingsBloc,
    required this.homeBloc,
    required this.diaryBloc,
    required this.calendarDayBloc,
  });

  @override
  State<MacroSplitDialog> createState() => _MacroSplitDialogState();
}

class _MacroSplitDialogState extends State<MacroSplitDialog> {
  // ── Standard (% ) mode ───────────────────────────────────────────────────
  static const double _defaultCarbsPct = 60;
  static const double _defaultProteinPct = 15;
  static const double _defaultFatPct = 25;

  double _carbsPct = _defaultCarbsPct;
  double _proteinPct = _defaultProteinPct;
  double _fatPct = _defaultFatPct;

  // ── Polar (g/kg) mode ────────────────────────────────────────────────────
  static const double _defaultProteinGPerKg = 2.2;
  static const double _defaultFatGPerKg = 0.8;

  bool _isPolarActive = false;
  double _proteinGPerKg = _defaultProteinGPerKg;
  double _fatGPerKg = _defaultFatGPerKg;
  double _weightKg = 70.0;

  bool _loaded = false;

  late final TextEditingController _carbsController;
  late final TextEditingController _proteinController;
  late final TextEditingController _fatController;
  late final TextEditingController _proteinGPerKgController;
  late final TextEditingController _fatGPerKgController;

  @override
  void initState() {
    super.initState();
    _carbsController = TextEditingController();
    _proteinController = TextEditingController();
    _fatController = TextEditingController();
    _proteinGPerKgController = TextEditingController();
    _fatGPerKgController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _proteinGPerKgController.dispose();
    _fatGPerKgController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final carbs = await widget.settingsBloc.getUserCarbGoalPct();
    final protein = await widget.settingsBloc.getUserProteinGoalPct();
    final fat = await widget.settingsBloc.getUserFatGoalPct();

    final polarDataSource = locator<PolarInfluxdbDataSource>();
    final isPolar = await polarDataSource.isPolarConfigured();
    double proteinGPerKg = _defaultProteinGPerKg;
    double fatGPerKg = _defaultFatGPerKg;
    double weightKg = 70.0;
    if (isPolar) {
      proteinGPerKg = await polarDataSource.getProteinGPerKg();
      fatGPerKg = await polarDataSource.getFatGPerKg();
      final user = await locator<ProfileBloc>().getUser();
      weightKg = user.weightKG;
    }

    if (!mounted) return;
    setState(() {
      _carbsPct = (carbs ?? _defaultCarbsPct / 100) * 100;
      _proteinPct = (protein ?? _defaultProteinPct / 100) * 100;
      _fatPct = (fat ?? _defaultFatPct / 100) * 100;
      _isPolarActive = isPolar;
      _proteinGPerKg = proteinGPerKg;
      _fatGPerKg = fatGPerKg;
      _weightKg = weightKg;
      _loaded = true;
    });
    _syncControllers();
  }

  void _syncControllers() {
    _carbsController.text = _carbsPct.round().toString();
    _proteinController.text = _proteinPct.round().toString();
    _fatController.text = _fatPct.round().toString();
    _proteinGPerKgController.text = _proteinGPerKg.toStringAsFixed(1);
    _fatGPerKgController.text = _fatGPerKg.toStringAsFixed(1);
  }

  /// Rebalance the two unmoved macros proportionally to their current
  /// ratio so the trio re-sums to 100. Each gets clamped to a 5% floor;
  /// anything that would push another macro below the floor is shaved
  /// off the larger of the two so the floors are always honoured.
  void _redistribute({
    required double moved,
    required void Function(double) setMoved,
    required double otherA,
    required void Function(double) setOtherA,
    required double otherB,
    required void Function(double) setOtherB,
    required double oldMoved,
  }) {
    final delta = moved - oldMoved;
    setMoved(moved);
    final totalOthers = otherA + otherB;
    if (totalOthers <= 0) return;
    final ratioA = otherA / totalOthers;
    final ratioB = otherB / totalOthers;
    var newA = otherA - delta * ratioA;
    var newB = otherB - delta * ratioB;
    if (newA < 5) {
      newB -= 5 - newA;
      newA = 5;
    }
    if (newB < 5) {
      newA -= 5 - newB;
      newB = 5;
    }
    setOtherA(newA);
    setOtherB(newB);
  }

  void _applyTextInput(TextEditingController controller, double currentValue,
      void Function(double) setter) {
    final parsed = int.tryParse(controller.text);
    if (parsed == null || parsed < 5 || parsed > 90) {
      _syncControllers();
      return;
    }
    setState(() => setter(parsed.toDouble()));
  }

  Future<void> _save() async {
    if (_isPolarActive) {
      final protein = double.tryParse(_proteinGPerKgController.text.trim()) ?? _defaultProteinGPerKg;
      final fat = double.tryParse(_fatGPerKgController.text.trim()) ?? _defaultFatGPerKg;
      final polarDataSource = locator<PolarInfluxdbDataSource>();
      await polarDataSource.saveProteinGPerKg(protein.clamp(0.5, 4.0));
      await polarDataSource.saveFatGPerKg(fat.clamp(0.3, 2.0));
    } else {
      // Flush any uncommitted text-field edits into state first.
      _applyTextInput(_carbsController, _carbsPct, (v) => _carbsPct = v);
      _applyTextInput(_proteinController, _proteinPct, (v) => _proteinPct = v);
      _applyTextInput(_fatController, _fatPct, (v) => _fatPct = v);
      await widget.settingsBloc.setMacroGoals(_carbsPct, _proteinPct, _fatPct);
      await widget.settingsBloc.updateTrackedDay(DateTime.now());
    }
    widget.settingsBloc.add(LoadSettingsEvent());
    widget.homeBloc.add(const LoadItemsEvent());
    widget.calendarDayBloc.add(const RefreshCalendarDayEvent());
    widget.diaryBloc.add(const LoadDiaryYearEvent());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final totalPct = _carbsPct.round() + _proteinPct.round() + _fatPct.round();
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              s.settingsMacroSplitLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: _loaded
                ? () {
                    setState(() {
                      if (_isPolarActive) {
                        _proteinGPerKg = _defaultProteinGPerKg;
                        _fatGPerKg = _defaultFatGPerKg;
                      } else {
                        _carbsPct = _defaultCarbsPct;
                        _proteinPct = _defaultProteinPct;
                        _fatPct = _defaultFatPct;
                      }
                    });
                    _syncControllers();
                  }
                : null,
            child: Text(s.buttonResetLabel),
          ),
        ],
      ),
      content: !_loaded
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isPolarActive) ...[
                    Text(
                      'Polar aktiv — Makros nach Körpergewicht (${_weightKg.toStringAsFixed(1)} kg)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _GPerKgRow(
                      label: s.proteinLabel,
                      color: Colors.blue,
                      gPerKg: _proteinGPerKg,
                      weightKg: _weightKg,
                      min: 0.5,
                      max: 4.0,
                      controller: _proteinGPerKgController,
                      onChanged: (v) => setState(() => _proteinGPerKg = v),
                    ),
                    _GPerKgRow(
                      label: s.fatLabel,
                      color: Colors.green,
                      gPerKg: _fatGPerKg,
                      weightKg: _weightKg,
                      min: 0.3,
                      max: 2.0,
                      controller: _fatGPerKgController,
                      onChanged: (v) => setState(() => _fatGPerKg = v),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(s.carbsLabel)),
                          Text(
                            'Rest der Kalorien',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                  Text(
                    '$totalPct% total',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _MacroRow(
                    label: s.carbsLabel,
                    value: _carbsPct,
                    color: Colors.orange,
                    controller: _carbsController,
                    semanticIdentifier: 'macro-split-carbs',
                    onSliderChanged: (v) => setState(() => _redistribute(
                          moved: v,
                          oldMoved: _carbsPct,
                          setMoved: (x) => _carbsPct = x,
                          otherA: _proteinPct,
                          setOtherA: (x) => _proteinPct = x,
                          otherB: _fatPct,
                          setOtherB: (x) => _fatPct = x,
                        )),
                    onSliderEnd: _syncControllers,
                    onTextSubmitted: () => _applyTextInput(
                        _carbsController, _carbsPct, (v) => _carbsPct = v),
                  ),
                  _MacroRow(
                    label: s.proteinLabel,
                    value: _proteinPct,
                    color: Colors.blue,
                    controller: _proteinController,
                    semanticIdentifier: 'macro-split-protein',
                    onSliderChanged: (v) => setState(() => _redistribute(
                          moved: v,
                          oldMoved: _proteinPct,
                          setMoved: (x) => _proteinPct = x,
                          otherA: _carbsPct,
                          setOtherA: (x) => _carbsPct = x,
                          otherB: _fatPct,
                          setOtherB: (x) => _fatPct = x,
                        )),
                    onSliderEnd: _syncControllers,
                    onTextSubmitted: () => _applyTextInput(_proteinController,
                        _proteinPct, (v) => _proteinPct = v),
                  ),
                  _MacroRow(
                    label: s.fatLabel,
                    value: _fatPct,
                    color: Colors.green,
                    controller: _fatController,
                    semanticIdentifier: 'macro-split-fat',
                    onSliderChanged: (v) => setState(() => _redistribute(
                          moved: v,
                          oldMoved: _fatPct,
                          setMoved: (x) => _fatPct = x,
                          otherA: _carbsPct,
                          setOtherA: (x) => _carbsPct = x,
                          otherB: _proteinPct,
                          setOtherB: (x) => _proteinPct = x,
                        )),
                    onSliderEnd: _syncControllers,
                    onTextSubmitted: () => _applyTextInput(
                        _fatController, _fatPct, (v) => _fatPct = v),
                  ),
                  ],  // end else branch
                ],
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.dialogCancelLabel),
        ),
        Semantics(
          identifier: 'macro-split-save',
          child: TextButton(
            onPressed: _loaded ? _save : null,
            child: Text(s.dialogOKLabel),
          ),
        ),
      ],
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final TextEditingController controller;
  final String semanticIdentifier;
  final ValueChanged<double> onSliderChanged;
  final VoidCallback onSliderEnd;
  final VoidCallback onTextSubmitted;

  const _MacroRow({
    required this.label,
    required this.value,
    required this.color,
    required this.controller,
    required this.semanticIdentifier,
    required this.onSliderChanged,
    required this.onSliderEnd,
    required this.onTextSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            SizedBox(
              width: 60,
              child: TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  suffixText: '%',
                  isDense: true,
                ),
                onSubmitted: (_) => onTextSubmitted(),
                onEditingComplete: onTextSubmitted,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.2),
          ),
          child: Semantics(
            identifier: semanticIdentifier,
            child: Slider(
              min: 5,
              max: 90,
              value: value.clamp(5, 90),
              divisions: 85,
              onChanged: (v) {
                final rounded = v.round().toDouble();
                if (100 - rounded >= 10) {
                  onSliderChanged(rounded);
                }
              },
              onChangeEnd: (_) => onSliderEnd(),
            ),
          ),
        ),
      ],
    );
  }
}

class _GPerKgRow extends StatelessWidget {
  final String label;
  final Color color;
  final double gPerKg;
  final double weightKg;
  final double min;
  final double max;
  final TextEditingController controller;
  final ValueChanged<double> onChanged;

  const _GPerKgRow({
    required this.label,
    required this.color,
    required this.gPerKg,
    required this.weightKg,
    required this.min,
    required this.max,
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final totalG = gPerKg * weightKg;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(label)),
            SizedBox(
              width: 60,
              child: TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  suffixText: 'g/kg',
                  isDense: true,
                ),
                onSubmitted: (_) {
                  final v = double.tryParse(controller.text) ?? gPerKg;
                  onChanged(v.clamp(min, max));
                },
                onEditingComplete: () {
                  final v = double.tryParse(controller.text) ?? gPerKg;
                  onChanged(v.clamp(min, max));
                },
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '= ${totalG.round()} g',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withValues(alpha: 0.2),
          ),
          child: Slider(
            min: min,
            max: max,
            divisions: ((max - min) * 10).round(),
            value: gPerKg.clamp(min, max),
            label: '${gPerKg.toStringAsFixed(1)} g/kg = ${totalG.round()} g',
            onChanged: (v) {
              final snapped = (v * 10).round() / 10;
              onChanged(snapped);
              controller.text = snapped.toStringAsFixed(1);
            },
          ),
        ),
      ],
    );
  }
}
