import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/data/data_source/polar_influxdb_data_source.dart';
import 'package:opennutritracker/core/domain/entity/calories_profile_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_entity.dart';
import 'package:opennutritracker/core/domain/entity/user_gender_entity.dart';
import 'package:opennutritracker/core/presentation/widgets/calories_profile_info_dialog.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/calendar_day_bloc.dart';
import 'package:opennutritracker/features/diary/presentation/bloc/diary_bloc.dart';
import 'package:opennutritracker/features/home/presentation/bloc/home_bloc.dart';
import 'package:opennutritracker/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:opennutritracker/features/settings/presentation/bloc/settings_bloc.dart';
import 'package:opennutritracker/generated/l10n.dart';

class CalculationsDialog extends StatefulWidget {
  final SettingsBloc settingsBloc;
  final ProfileBloc profileBloc;
  final HomeBloc homeBloc;
  final DiaryBloc diaryBloc;
  final CalendarDayBloc calendarDayBloc;

  const CalculationsDialog({
    super.key,
    required this.settingsBloc,
    required this.profileBloc,
    required this.homeBloc,
    required this.diaryBloc,
    required this.calendarDayBloc,
  });

  @override
  State<CalculationsDialog> createState() => _CalculationsDialogState();
}

class _CalculationsDialogState extends State<CalculationsDialog> {
  static const double _maxKcalAdjustment = 1000;
  static const double _minKcalAdjustment = -1000;
  static const int _kcalDivisions = 200;
  double _kcalAdjustmentSelection = 0;

  // ── Percentage mode (Polar off) ──────────────────────────────────────────
  static const double _defaultCarbsPctSelection = 0.6;
  static const double _defaultFatPctSelection = 0.25;
  static const double _defaultProteinPctSelection = 0.15;

  double _carbsPctSelection = _defaultCarbsPctSelection * 100;
  double _proteinPctSelection = _defaultProteinPctSelection * 100;
  double _fatPctSelection = _defaultFatPctSelection * 100;

  // ── Body-weight mode (Polar on) ──────────────────────────────────────────
  static const double _defaultProteinGPerKg = 2.2;
  static const double _defaultFatGPerKg = 0.8;

  bool _isPolarActive = false;
  double _proteinGPerKgSelection = _defaultProteinGPerKg;
  double _fatGPerKgSelection = _defaultFatGPerKg;

  // ── Text controllers ─────────────────────────────────────────────────────
  late TextEditingController _kcalAdjustmentController;
  late TextEditingController _carbsController;
  late TextEditingController _proteinController;
  late TextEditingController _fatController;
  late TextEditingController _proteinGPerKgController;
  late TextEditingController _fatGPerKgController;

  UserEntity? _user;

  @override
  void initState() {
    super.initState();
    _kcalAdjustmentController =
        TextEditingController(text: _kcalAdjustmentSelection.round().toString());
    _carbsController =
        TextEditingController(text: _carbsPctSelection.round().toString());
    _proteinController =
        TextEditingController(text: _proteinPctSelection.round().toString());
    _fatController =
        TextEditingController(text: _fatPctSelection.round().toString());
    _proteinGPerKgController =
        TextEditingController(text: _defaultProteinGPerKg.toStringAsFixed(1));
    _fatGPerKgController =
        TextEditingController(text: _defaultFatGPerKg.toStringAsFixed(1));
  }

  @override
  void dispose() {
    _kcalAdjustmentController.dispose();
    _carbsController.dispose();
    _proteinController.dispose();
    _fatController.dispose();
    _proteinGPerKgController.dispose();
    _fatGPerKgController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initializeValues();
  }

  Future<void> _initializeValues() async {
    final kcalAdjustment = await widget.settingsBloc.getKcalAdjustment() * 1.0;
    final userCarbsPct = await widget.settingsBloc.getUserCarbGoalPct();
    final userProteinPct = await widget.settingsBloc.getUserProteinGoalPct();
    final userFatPct = await widget.settingsBloc.getUserFatGoalPct();
    final user = await widget.profileBloc.getUser();

    final polarDataSource = locator<PolarInfluxdbDataSource>();
    final isPolar = await polarDataSource.isPolarConfigured();
    double proteinGPerKg = _defaultProteinGPerKg;
    double fatGPerKg = _defaultFatGPerKg;
    if (isPolar) {
      proteinGPerKg = await polarDataSource.getProteinGPerKg();
      fatGPerKg = await polarDataSource.getFatGPerKg();
    }

    if (!mounted) return;
    setState(() {
      _kcalAdjustmentSelection = kcalAdjustment;
      _carbsPctSelection = (userCarbsPct ?? _defaultCarbsPctSelection) * 100;
      _proteinPctSelection =
          (userProteinPct ?? _defaultProteinPctSelection) * 100;
      _fatPctSelection = (userFatPct ?? _defaultFatPctSelection) * 100;
      _user = user;
      _isPolarActive = isPolar;
      _proteinGPerKgSelection = proteinGPerKg;
      _fatGPerKgSelection = fatGPerKg;
    });
    _kcalAdjustmentController.text = _kcalAdjustmentSelection.round().toString();
    _carbsController.text = _carbsPctSelection.round().toString();
    _proteinController.text = _proteinPctSelection.round().toString();
    _fatController.text = _fatPctSelection.round().toString();
    _proteinGPerKgController.text = _proteinGPerKgSelection.toStringAsFixed(1);
    _fatGPerKgController.text = _fatGPerKgSelection.toStringAsFixed(1);
  }

  void _syncPctControllersToState() {
    _carbsController.text = _carbsPctSelection.round().toString();
    _proteinController.text = _proteinPctSelection.round().toString();
    _fatController.text = _fatPctSelection.round().toString();
  }

  void _syncGPerKgControllersToState() {
    _proteinGPerKgController.text = _proteinGPerKgSelection.toStringAsFixed(1);
    _fatGPerKgController.text = _fatGPerKgSelection.toStringAsFixed(1);
  }

  void _applyDirectMacroInput(
      TextEditingController controller, void Function(double) setter) {
    final parsed = int.tryParse(controller.text);
    if (parsed == null || parsed < 5 || parsed > 90) {
      _syncPctControllersToState();
      return;
    }
    setState(() => setter(parsed.toDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final weightKg = _user?.weightKG ?? 70.0;

    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              S.of(context).settingsCalculationsLabel,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            child: Text(S.of(context).buttonResetLabel),
            onPressed: () {
              setState(() {
                _kcalAdjustmentSelection = 0;
                if (_isPolarActive) {
                  _proteinGPerKgSelection = _defaultProteinGPerKg;
                  _fatGPerKgSelection = _defaultFatGPerKg;
                  _syncGPerKgControllersToState();
                } else {
                  _carbsPctSelection = _defaultCarbsPctSelection * 100;
                  _proteinPctSelection = _defaultProteinPctSelection * 100;
                  _fatPctSelection = _defaultFatPctSelection * 100;
                  _syncPctControllersToState();
                }
              });
              _kcalAdjustmentController.text = '0';
            },
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField(
              isExpanded: true,
              decoration: InputDecoration(
                enabled: false,
                filled: false,
                labelText: S.of(context).calculationsTDEELabel,
              ),
              items: [
                DropdownMenuItem(
                  child: Text(
                    'Mifflin-St. Jeor (1990) ${S.of(context).calculationsRecommendedLabel}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              onChanged: null,
            ),
            const SizedBox(height: 32),
            if (_user?.gender == UserGenderEntity.nonBinary) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune_outlined),
                title: Text(S.of(context).caloriesProfileInfoTitle),
                subtitle: Text(
                  (_user?.caloriesProfile ?? CaloriesProfileEntity.averaged)
                      .getName(context),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openCaloriesProfileDialog,
              ),
              const SizedBox(height: 8),
            ],
            // ── Kcal adjustment (always shown) ───────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.of(context).dailyKcalAdjustmentLabel,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: _kcalAdjustmentController,
                    keyboardType: const TextInputType.numberWithOptions(
                        signed: true, decimal: false),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                    ],
                    textAlign: TextAlign.right,
                    decoration: InputDecoration(
                      suffixText: S.of(context).kcalLabel,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _applyKcalInput(),
                    onEditingComplete: _applyKcalInput,
                  ),
                ),
              ],
            ),
            Slider(
              min: _minKcalAdjustment,
              max: _maxKcalAdjustment,
              divisions: _kcalDivisions,
              value: _kcalAdjustmentSelection,
              label:
                  '${_kcalAdjustmentSelection.round()} ${S.of(context).kcalLabel}',
              onChanged: (value) {
                setState(() => _kcalAdjustmentSelection = value);
                _kcalAdjustmentController.text = value.round().toString();
              },
            ),
            const SizedBox(height: 16),
            // ── Macro distribution ────────────────────────────────────────────
            Text(
              S.of(context).macroDistributionLabel,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (_isPolarActive) ...[
              // ── Polar mode: g/kg sliders ────────────────────────────────────
              Text(
                'Polar aktiv — Makros nach Körpergewicht (${weightKg.toStringAsFixed(1)} kg)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              _buildGPerKgRow(
                label: S.of(context).proteinLabel,
                color: Colors.blue,
                gPerKg: _proteinGPerKgSelection,
                weightKg: weightKg,
                min: 0.5,
                max: 4.0,
                controller: _proteinGPerKgController,
                onSliderChanged: (v) =>
                    setState(() => _proteinGPerKgSelection = v),
                onTextSubmitted: () {
                  final v =
                      double.tryParse(_proteinGPerKgController.text) ?? _defaultProteinGPerKg;
                  setState(() => _proteinGPerKgSelection = v.clamp(0.5, 4.0));
                  _syncGPerKgControllersToState();
                },
              ),
              _buildGPerKgRow(
                label: S.of(context).fatLabel,
                color: Colors.green,
                gPerKg: _fatGPerKgSelection,
                weightKg: weightKg,
                min: 0.3,
                max: 2.0,
                controller: _fatGPerKgController,
                onSliderChanged: (v) =>
                    setState(() => _fatGPerKgSelection = v),
                onTextSubmitted: () {
                  final v =
                      double.tryParse(_fatGPerKgController.text) ?? _defaultFatGPerKg;
                  setState(() => _fatGPerKgSelection = v.clamp(0.3, 2.0));
                  _syncGPerKgControllersToState();
                },
              ),
              // Carbs info (read-only — fills remaining kcal)
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
                    Expanded(
                      child: Text(
                        S.of(context).carbsLabel,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      'Rest der Kalorien',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ] else ...[
              // ── Standard mode: % sliders ────────────────────────────────────
              Text(
                '${_carbsPctSelection.round() + _proteinPctSelection.round() + _fatPctSelection.round()}% total',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              _buildMacroRow(
                S.of(context).carbsLabel,
                _carbsPctSelection,
                Colors.orange,
                _carbsController,
                onSliderChanged: (value) {
                  setState(() {
                    double delta = value - _carbsPctSelection;
                    _carbsPctSelection = value;
                    double proteinRatio = _proteinPctSelection /
                        (_proteinPctSelection + _fatPctSelection);
                    double fatRatio = _fatPctSelection /
                        (_proteinPctSelection + _fatPctSelection);
                    _proteinPctSelection -= delta * proteinRatio;
                    _fatPctSelection -= delta * fatRatio;
                    if (_proteinPctSelection < 5) {
                      _fatPctSelection -= 5 - _proteinPctSelection;
                      _proteinPctSelection = 5;
                    }
                    if (_fatPctSelection < 5) {
                      _proteinPctSelection -= 5 - _fatPctSelection;
                      _fatPctSelection = 5;
                    }
                  });
                  _syncPctControllersToState();
                },
                onTextSubmitted: () => _applyDirectMacroInput(
                    _carbsController, (v) => _carbsPctSelection = v),
              ),
              _buildMacroRow(
                S.of(context).proteinLabel,
                _proteinPctSelection,
                Colors.blue,
                _proteinController,
                onSliderChanged: (value) {
                  setState(() {
                    double delta = value - _proteinPctSelection;
                    _proteinPctSelection = value;
                    double carbsRatio = _carbsPctSelection /
                        (_carbsPctSelection + _fatPctSelection);
                    double fatRatio = _fatPctSelection /
                        (_carbsPctSelection + _fatPctSelection);
                    _carbsPctSelection -= delta * carbsRatio;
                    _fatPctSelection -= delta * fatRatio;
                    if (_carbsPctSelection < 5) {
                      _fatPctSelection -= 5 - _carbsPctSelection;
                      _carbsPctSelection = 5;
                    }
                    if (_fatPctSelection < 5) {
                      _carbsPctSelection -= 5 - _fatPctSelection;
                      _fatPctSelection = 5;
                    }
                  });
                  _syncPctControllersToState();
                },
                onTextSubmitted: () => _applyDirectMacroInput(
                    _proteinController, (v) => _proteinPctSelection = v),
              ),
              _buildMacroRow(
                S.of(context).fatLabel,
                _fatPctSelection,
                Colors.green,
                _fatController,
                onSliderChanged: (value) {
                  setState(() {
                    double delta = value - _fatPctSelection;
                    _fatPctSelection = value;
                    double carbsRatio = _carbsPctSelection /
                        (_carbsPctSelection + _proteinPctSelection);
                    double proteinRatio = _proteinPctSelection /
                        (_carbsPctSelection + _proteinPctSelection);
                    _carbsPctSelection -= delta * carbsRatio;
                    _proteinPctSelection -= delta * proteinRatio;
                    if (_carbsPctSelection < 5) {
                      _proteinPctSelection -= 5 - _carbsPctSelection;
                      _carbsPctSelection = 5;
                    }
                    if (_proteinPctSelection < 5) {
                      _carbsPctSelection -= 5 - _proteinPctSelection;
                      _proteinPctSelection = 5;
                    }
                  });
                  _syncPctControllersToState();
                },
                onTextSubmitted: () => _applyDirectMacroInput(
                    _fatController, (v) => _fatPctSelection = v),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogCancelLabel),
        ),
        TextButton(
          onPressed: _saveCalculationSettings,
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    );
  }

  void _applyKcalInput() {
    final parsed = int.tryParse(_kcalAdjustmentController.text);
    if (parsed == null) {
      _kcalAdjustmentController.text =
          _kcalAdjustmentSelection.round().toString();
      return;
    }
    final clamped =
        parsed.clamp(_minKcalAdjustment.toInt(), _maxKcalAdjustment.toInt());
    setState(() => _kcalAdjustmentSelection = clamped.toDouble());
    _kcalAdjustmentController.text = clamped.toString();
  }

  Widget _buildGPerKgRow({
    required String label,
    required Color color,
    required double gPerKg,
    required double weightKg,
    required double min,
    required double max,
    required TextEditingController controller,
    required ValueChanged<double> onSliderChanged,
    required VoidCallback onTextSubmitted,
  }) {
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
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  suffixText: 'g/kg',
                  isDense: true,
                ),
                onSubmitted: (_) => onTextSubmitted(),
                onEditingComplete: onTextSubmitted,
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
              onSliderChanged(
                  (v * 10).round() / 10); // snap to 0.1 steps
              controller.text =
                  ((v * 10).round() / 10).toStringAsFixed(1);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMacroRow(
    String label,
    double value,
    Color color,
    TextEditingController controller, {
    required ValueChanged<double> onSliderChanged,
    required VoidCallback onTextSubmitted,
  }) {
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
          ),
        ),
      ],
    );
  }

  void _normalizeMacros() {
    _carbsPctSelection = _carbsPctSelection.roundToDouble();
    _proteinPctSelection = _proteinPctSelection.roundToDouble();
    _fatPctSelection = _fatPctSelection.roundToDouble();

    double total =
        _carbsPctSelection + _proteinPctSelection + _fatPctSelection;

    if (total != 100) {
      double factor = 100 / total;
      _carbsPctSelection = (_carbsPctSelection * factor).roundToDouble();
      _proteinPctSelection = (_proteinPctSelection * factor).roundToDouble();
      _fatPctSelection = 100 - _carbsPctSelection - _proteinPctSelection;
      if (_fatPctSelection < 5) {
        _fatPctSelection = 5;
        double remaining = 95;
        double ratio =
            _carbsPctSelection / (_carbsPctSelection + _proteinPctSelection);
        _carbsPctSelection = (remaining * ratio).roundToDouble();
        _proteinPctSelection = remaining - _carbsPctSelection;
      }
    }
  }

  void _saveCalculationSettings() async {
    _applyKcalInput();
    widget.settingsBloc
        .setKcalAdjustment(_kcalAdjustmentSelection.toInt().toDouble());

    if (_isPolarActive) {
      final protein =
          double.tryParse(_proteinGPerKgController.text.trim()) ??
              _defaultProteinGPerKg;
      final fat =
          double.tryParse(_fatGPerKgController.text.trim()) ??
              _defaultFatGPerKg;
      final dataSource = locator<PolarInfluxdbDataSource>();
      await dataSource.saveProteinGPerKg(protein.clamp(0.5, 4.0));
      await dataSource.saveFatGPerKg(fat.clamp(0.3, 2.0));
    } else {
      _applyDirectMacroInput(_carbsController, (v) => _carbsPctSelection = v);
      _applyDirectMacroInput(
          _proteinController, (v) => _proteinPctSelection = v);
      _applyDirectMacroInput(_fatController, (v) => _fatPctSelection = v);
      _normalizeMacros();
      widget.settingsBloc.setMacroGoals(
        _carbsPctSelection,
        _proteinPctSelection,
        _fatPctSelection,
      );
    }

    widget.settingsBloc.add(LoadSettingsEvent());
    widget.profileBloc.add(LoadProfileEvent());
    widget.homeBloc.add(LoadItemsEvent());
    widget.settingsBloc.updateTrackedDay(DateTime.now());
    widget.diaryBloc.add(LoadDiaryYearEvent());
    widget.calendarDayBloc.add(RefreshCalendarDayEvent());

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openCaloriesProfileDialog() async {
    final user = _user;
    if (user == null) return;
    final selected = await showDialog<CaloriesProfileEntity>(
      context: context,
      builder: (context) => CaloriesProfileInfoDialog(
        initialProfile:
            user.caloriesProfile ?? CaloriesProfileEntity.averaged,
      ),
    );
    if (selected == null) return;
    user.caloriesProfile = selected;
    await widget.profileBloc.updateUser(user);
    if (!mounted) return;
    setState(() {
      _user = user;
    });
  }
}
