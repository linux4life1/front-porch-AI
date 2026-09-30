// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Entries the user ticked on one character. Nothing is included that
/// they did not check.
class CharacterLoreSelection {
  const CharacterLoreSelection({
    required this.characterName,
    required this.entries,
  });

  final String characterName;
  final List<LorebookEntry> entries;
}

/// Pick a character, then tick which of that character's lore entries to
/// copy. Returns null when cancelled. Unlike Import from character on the
/// card editor, this never copies the whole book.
Future<CharacterLoreSelection?> showPickCharacterLoreEntriesDialog({
  required BuildContext context,
  required List<CharacterCard> characters,
}) {
  final candidates =
      characters.where((c) => (c.lorebook?.entries.length ?? 0) > 0).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return showDialog<CharacterLoreSelection>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _PickCharacterLoreDialog(candidates: candidates),
  );
}

class _PickCharacterLoreDialog extends StatefulWidget {
  const _PickCharacterLoreDialog({required this.candidates});

  final List<CharacterCard> candidates;

  @override
  State<_PickCharacterLoreDialog> createState() =>
      _PickCharacterLoreDialogState();
}

class _PickCharacterLoreDialogState extends State<_PickCharacterLoreDialog> {
  final _search = TextEditingController();
  String _query = '';
  CharacterCard? _character;
  final Set<int> _checked = {};

  /// One exists-check per portrait for the life of this dialog. The list
  /// rebuilds on every search keystroke.
  final Map<String, ImageProvider?> _avatarCache = {};

  ImageProvider? _avatar(CharacterCard card) {
    final path = card.imagePath;
    if (path == null || path.isEmpty) return null;
    return _avatarCache.putIfAbsent(
      path,
      () =>
          File(path)
              .existsSync() // io-ok: memoized once per portrait path
          ? FileImage(File(path))
          : null,
    );
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CharacterCard> get _characters {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.candidates;
    return [
      for (final c in widget.candidates)
        if (c.name.toLowerCase().contains(q)) c,
    ];
  }

  List<LorebookEntry> get _entries => _character?.lorebook?.entries ?? const [];

  List<int> get _visible {
    final q = _query.trim().toLowerCase();
    final out = <int>[];
    for (var i = 0; i < _entries.length; i++) {
      if (q.isEmpty) {
        out.add(i);
        continue;
      }
      final e = _entries[i];
      final hay = '${e.displayName}\n${e.key}\n${e.content}'.toLowerCase();
      if (hay.contains(q)) out.add(i);
    }
    return out;
  }

  void _openCharacter(CharacterCard character) {
    setState(() {
      _character = character;
      _checked.clear();
      _query = '';
      _search.clear();
    });
  }

  void _backToCharacters() {
    setState(() {
      _character = null;
      _checked.clear();
      _query = '';
      _search.clear();
    });
  }

  void _toggle(int index) {
    setState(() {
      if (!_checked.remove(index)) _checked.add(index);
    });
  }

  void _import() {
    final character = _character;
    if (character == null || _checked.isEmpty) return;
    final indexes = _checked.toList()..sort();
    Navigator.pop(
      context,
      CharacterLoreSelection(
        characterName: character.name,
        entries: [
          for (final i in indexes) character.lorebook!.entries[i].clone(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickingEntries = _character != null;
    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, pickingEntries),
            if (widget.candidates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 14,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: pickingEntries
                        ? 'Search entries…'
                        : 'Search characters…',
                    hintStyle: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search,
                      size: 20,
                      color: AppColors.textTertiary(context),
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerOf(context),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            Flexible(
              child: widget.candidates.isEmpty
                  ? const _EmptyLine(
                      title: 'No lore to import',
                      body:
                          'None of your characters have lorebook entries yet.',
                    )
                  : pickingEntries
                  ? _entryList(context)
                  : _characterList(context),
            ),
            _footer(context, pickingEntries),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context, bool pickingEntries) {
    final name = _character?.name ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  pickingEntries ? 'Choose entries' : 'From character',
                  style: TextStyle(
                    color: AppColors.textPrimary(context),
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  pickingEntries
                      ? 'Tick what to copy from $name. The rest stays on the card.'
                      : 'Pick a character, then choose entries for this place.',
                  style: TextStyle(
                    color: AppColors.textTertiary(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: AppColors.textTertiary(context),
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _characterList(BuildContext context) {
    final rows = _characters;
    if (rows.isEmpty) {
      return const _EmptyLine(
        title: 'No matches',
        body: 'Try a different name.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final c = rows[i];
        final count = c.lorebook!.entries.length;
        final avatar = _avatar(c);
        final initial = c.name.isEmpty ? '?' : c.name[0].toUpperCase();
        return Material(
          color: AppColors.surfaceContainerOf(context),
          borderRadius: BorderRadius.circular(12),
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: AppColors.formMasterAccent.withValues(
                alpha: 0.18,
              ),
              backgroundImage: avatar,
              child: avatar != null
                  ? null
                  : Text(
                      initial,
                      style: TextStyle(
                        color: AppColors.formMasterAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
            ),
            title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('$count ${count == 1 ? 'entry' : 'entries'}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openCharacter(c),
          ),
        );
      },
    );
  }

  Widget _entryList(BuildContext context) {
    final visible = _visible;
    if (visible.isEmpty) {
      return const _EmptyLine(
        title: 'No matches',
        body: 'Try a different word, or clear the search.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: visible.length,
      itemBuilder: (context, row) {
        final index = visible[row];
        final entry = _entries[index];
        final detail = entry.key.isNotEmpty ? entry.key : entry.content;
        return CheckboxListTile(
          value: _checked.contains(index),
          onChanged: (_) => _toggle(index),
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: detail.isEmpty
              ? null
              : Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis),
        );
      },
    );
  }

  Widget _footer(BuildContext context, bool pickingEntries) {
    final n = _checked.length;
    final addLabel = n == 0
        ? 'Add selected'
        : 'Add $n ${n == 1 ? 'entry' : 'entries'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        children: [
          if (pickingEntries) ...[
            TextButton(
              onPressed: _backToCharacters,
              child: const Text('Characters'),
            ),
            TextButton(
              onPressed: _visible.isEmpty
                  ? null
                  : () => setState(() => _checked.addAll(_visible)),
              child: const Text('Select all'),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          if (pickingEntries) ...[
            const SizedBox(width: 4),
            FilledButton(
              onPressed: n == 0 ? null : _import,
              child: Text(addLabel),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
