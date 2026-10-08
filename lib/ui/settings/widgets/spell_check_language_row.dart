// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart'
    show DesktopSpellCheckService, StorageService, kSpellCheckOff;
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart'
    show GuardedPicker, StyledDropdown;
import 'package:front_porch_ai/utils/utils.dart';

/// Sentinel dropdown value for the "Load a dictionary file…" entry. Not a
/// language, so it is intercepted in onChanged and never stored.
const String _kAddDictionary = '__add_dictionary__';

/// Picks the language prose fields are spell checked against.
///
/// This exists because the language someone *types* has nothing to do with the
/// language their operating system is set to. A user running a German desktop
/// and role-playing in English was getting every English word underlined,
/// because both spell check paths resolved the OS locale. Defaulting to
/// English and letting people say otherwise is the fix; this is where they say
/// it.
///
/// The menu lists what the platform can actually check — hunspell dictionaries
/// found on disk (Linux), `NSSpellChecker.availableLanguages` (macOS),
/// `ISpellCheckerFactory` supported languages (Windows) — so it can never
/// offer a language that would silently do nothing.
class SpellCheckLanguageRow extends StatefulWidget {
  const SpellCheckLanguageRow({super.key});

  @override
  State<SpellCheckLanguageRow> createState() => _SpellCheckLanguageRowState();
}

class _SpellCheckLanguageRowState extends State<SpellCheckLanguageRow> {
  List<String> _languages = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Copies a hunspell `.aff`/`.dic` pair the user picked into
  /// `~/.local/share/hunspell`, which is the first directory the Linux plugin
  /// searches — so the language appears in this menu, and wins over both the
  /// system's copy and the ones we bundle.
  ///
  /// Linux only, and not an omission elsewhere: NSSpellChecker and
  /// ISpellChecker are closed and consume only their own installed
  /// dictionaries, so there is nowhere on macOS or Windows to put such a file.
  /// Those users add a language through the OS instead.
  Future<void> _addDictionaryFile() async {
    final picked = await GuardedPicker.pickFiles(
      context,
      category: 'dictionary',
      dialogTitle: 'Choose a hunspell .dic or .aff file',
      allowedExtensions: ['dic', 'aff'],
      type: FileType.custom,
    );
    final files = picked?.files ?? const [];
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;

    // Either half identifies the pair; both must be present to be usable.
    final stem = p.withoutExtension(path);
    final aff = File('$stem.aff');
    final dic = File('$stem.dic');
    String? failure;
    if (!aff.existsSync() || !dic.existsSync()) {
      failure =
          'A dictionary is two files — ${p.basename(stem)}.aff and '
          '${p.basename(stem)}.dic. Only one of them is in that folder.';
    } else {
      try {
        final target = Directory(
          p.join(Platform.environment['HOME'] ?? '', '.local/share/hunspell'),
        );
        await target.create(recursive: true);
        final name = p.basename(stem);
        await aff.copy(p.join(target.path, '$name.aff'));
        await dic.copy(p.join(target.path, '$name.dic'));
        if (mounted) {
          await context.read<StorageService>().setSpellCheckLanguage(name);
        }
      } catch (e) {
        failure = 'Could not install that dictionary: $e';
      }
    }

    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure)));
    }
    await _load();
  }

  Future<void> _load() async {
    final found = await DesktopSpellCheckService.availableLanguages();
    if (!mounted) return;
    setState(() {
      // Always include the current selection even if the platform did not
      // report it — otherwise a dictionary uninstalled since the setting was
      // saved would leave the dropdown with a value that is not in its own
      // item list, which throws.
      _languages = sortedByLabel([
        ...found,
        if (DesktopSpellCheckService.activeLanguage != kSpellCheckOff)
          DesktopSpellCheckService.activeLanguage,
      ]);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spell Check Language',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The language you write in — not your system language. '
                  'Set this to the language you chat with characters in.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (_loading)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            StyledDropdown<String>(
              width: 220,
              value: storage.spellCheckLanguage,
              items: [
                const DropdownMenuItem(
                  value: kSpellCheckOff,
                  child: Text('Off'),
                ),
                for (final tag in _languages)
                  DropdownMenuItem(
                    value: tag,
                    child: Text(spellCheckLanguageLabel(tag)),
                  ),
                // Linux only — see _addDictionaryFile for why this cannot
                // exist on macOS or Windows.
                if (Platform.isLinux)
                  const DropdownMenuItem(
                    value: _kAddDictionary,
                    child: Text('Load a dictionary file…'),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                if (value == _kAddDictionary) {
                  _addDictionaryFile();
                  return;
                }
                storage.setSpellCheckLanguage(value);
              },
            ),
        ],
      ),
    );
  }
}
