// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pick another character and copy their lorebook entries into the current
// editor (replaces the old "character world clone" workflow).

import 'dart:io';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Returns cloned lore entries from the chosen character, or null if cancelled.
Future<List<LorebookEntry>?> showImportCharacterLoreDialog({
  required BuildContext context,
  required List<CharacterCard> characters,
  String? excludeCharacterName,
}) {
  final candidates = characters
      .where((c) {
        if (excludeCharacterName != null && c.name == excludeCharacterName) {
          return false;
        }
        return (c.lorebook?.entries.length ?? 0) > 0;
      })
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  return showDialog<List<LorebookEntry>>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _ImportCharacterLoreDialog(candidates: candidates),
  );
}

class _ImportCharacterLoreDialog extends StatefulWidget {
  final List<CharacterCard> candidates;

  const _ImportCharacterLoreDialog({required this.candidates});

  @override
  State<_ImportCharacterLoreDialog> createState() =>
      _ImportCharacterLoreDialogState();
}

class _ImportCharacterLoreDialogState extends State<_ImportCharacterLoreDialog> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CharacterCard> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.candidates;
    return [
      for (final c in widget.candidates)
        if (c.name.toLowerCase().contains(q)) c,
    ];
  }

  void _pick(CharacterCard c) {
    final clones = c.lorebook!.entries.map((e) => e.clone()).toList();
    Navigator.pop(context, clones);
  }

  @override
  Widget build(BuildContext context) {
    final emptyLibrary = widget.candidates.isEmpty;
    final filtered = _filtered;

    return Dialog(
      backgroundColor: AppColors.surfaceOf(context),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.formMasterAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person_search_rounded,
                      color: AppColors.formMasterAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Import from character',
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Copy lore into this book · no World created',
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
            ),

            if (!emptyLibrary) ...[
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
                    hintText: 'Search characters…',
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
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppColors.formMasterAccent.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ],

            Flexible(
              child: emptyLibrary
                  ? _EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'No lore to import',
                      body:
                          'None of your other characters have lorebook entries yet.',
                    )
                  : filtered.isEmpty
                      ? _EmptyState(
                          icon: Icons.search_off,
                          title: 'No matches',
                          body: 'Try a different name.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final c = filtered[i];
                            final count = c.lorebook!.entries.length;
                            return _CharacterLoreTile(
                              character: c,
                              entryCount: count,
                              onTap: () => _pick(c),
                            );
                          },
                        ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Row(
                children: [
                  if (!emptyLibrary)
                    Text(
                      '${widget.candidates.length} with lore',
                      style: TextStyle(
                        color: AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary(context),
                    ),
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CharacterLoreTile extends StatefulWidget {
  final CharacterCard character;
  final int entryCount;
  final VoidCallback onTap;

  const _CharacterLoreTile({
    required this.character,
    required this.entryCount,
    required this.onTap,
  });

  @override
  State<_CharacterLoreTile> createState() => _CharacterLoreTileState();
}

class _CharacterLoreTileState extends State<_CharacterLoreTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.character;
    final path = c.imagePath;
    final hasFile = path != null && path.isNotEmpty && File(path).existsSync();

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _hover
                  ? AppColors.formMasterAccent.withValues(alpha: 0.10)
                  : AppColors.surfaceContainerOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _hover
                    ? AppColors.formMasterAccent.withValues(alpha: 0.45)
                    : AppColors.borderOf(context).withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      AppColors.formMasterAccent.withValues(alpha: 0.18),
                  backgroundImage: hasFile ? FileImage(File(path)) : null,
                  child: hasFile
                      ? null
                      : Text(
                          c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                          style: TextStyle(
                            color: AppColors.formMasterAccent,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${widget.entryCount} '
                        '${widget.entryCount == 1 ? 'entry' : 'entries'}',
                        style: TextStyle(
                          color: AppColors.textTertiary(context),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.formMasterAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Copy',
                    style: TextStyle(
                      color: AppColors.formMasterAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 40, color: AppColors.textTertiary(context)),
          const SizedBox(height: 12),
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
