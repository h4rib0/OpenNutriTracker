import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:opennutritracker/core/data/data_source/supabase_recovery_data_source.dart';
import 'package:opennutritracker/core/domain/usecase/supabase_backup_usecase.dart';
import 'package:opennutritracker/core/utils/locator.dart';
import 'package:opennutritracker/generated/l10n.dart';

/// Fork-only: shows this install's Supabase recovery code and lets the user
/// claim the code of an earlier install, which moves that install's backed
/// up custom meals, recipes and nutrient overrides over to this one.
class RecoveryCodeDialog extends StatefulWidget {
  /// Defaults to the locator's instance; tests pass their own.
  final SupabaseBackupUsecase? backupUsecase;

  const RecoveryCodeDialog({super.key, this.backupUsecase});

  @override
  State<RecoveryCodeDialog> createState() => _RecoveryCodeDialogState();
}

class _RecoveryCodeDialogState extends State<RecoveryCodeDialog> {
  late final SupabaseBackupUsecase _backup =
      widget.backupUsecase ?? locator<SupabaseBackupUsecase>();
  final _input = TextEditingController();

  late Future<String?> _code = _backup.getRecoveryCode();
  bool _restoring = false;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _restoring = true;
      _message = null;
    });
    String message;
    var isError = true;
    try {
      final current = await _code;
      final isOwn =
          current != null &&
          SupabaseRecoveryDataSource.normalize(_input.text) ==
              SupabaseRecoveryDataSource.normalize(current);
      final moved = await _backup.restoreWithCode(_input.text);
      if (moved == null) {
        message = 'Dieser Code ist auf dem Server nicht bekannt.';
      } else {
        isError = false;
        message = isOwn
            ? 'Der Code gehört bereits zu dieser Installation.'
            : moved == 0
            ? 'Code eingelöst — in der Sicherung lagen keine Einträge.'
            : '${moved == 1 ? '1 Eintrag' : '$moved Einträge'} übernommen. '
                  'Eigene Mahlzeiten und Rezepte wurden wiederhergestellt.';
        _input.clear();
        _code = _backup.getRecoveryCode();
      }
    } on FormatException {
      message = 'Kein gültiger Code (20 Zeichen, z. B. ABCD-EFGH-…).';
    } catch (e) {
      message = 'Wiederherstellen fehlgeschlagen: $e';
    }
    if (!mounted) return;
    setState(() {
      _restoring = false;
      _message = message;
      _messageIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Wiederherstellungscode'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mit diesem Code holst du deine in Supabase gesicherten eigenen '
              'Mahlzeiten, Rezepte und Nährwert-Ergänzungen nach einer '
              'Neuinstallation zurück. Notiere ihn dir — er steht auch im '
              'JSON-Export.',
            ),
            const SizedBox(height: 16),
            FutureBuilder<String?>(
              future: _code,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final code = snapshot.data;
                if (code == null) {
                  return Text(
                    'Gerade nicht verfügbar — keine Verbindung zu Supabase.',
                    style: TextStyle(color: theme.colorScheme.error),
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        code,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Semantics(
                      identifier: 'recovery-code-copy',
                      child: IconButton(
                        icon: const Icon(Icons.copy_rounded),
                        tooltip: 'Kopieren',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            const SnackBar(content: Text('Code kopiert')),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 32),
            Text(
              'Code einer früheren Installation einlösen',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Semantics(
              identifier: 'recovery-code-input',
              child: TextField(
                controller: _input,
                enabled: !_restoring,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(
                _message!,
                style: TextStyle(
                  color: _messageIsError
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        Semantics(
          identifier: 'recovery-code-restore',
          child: TextButton(
            onPressed: _restoring ? null : _restore,
            child: _restoring
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Wiederherstellen'),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).dialogOKLabel),
        ),
      ],
    );
  }
}
