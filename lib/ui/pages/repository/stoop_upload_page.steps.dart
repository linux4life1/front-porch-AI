// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

part of 'stoop_upload_page.dart';

extension _StoopUploadPageStateSteps on _StoopUploadPageState {
  // Step 0 — pick a local character, group, or place. Extracted to
  // StoopPickStep (stoop_pick_step.dart), which is folder-aware: the grids
  // follow the home grid's folder hierarchy via the shared
  // buildFolderPickView rules.
  Widget _pickStep() {
    return StoopPickStep(
      selectedCard: _selected,
      selectedGroup: _selectedGroup,
      selectedWorldId: _selectedWorld?.id,
      onSelectCard: _select,
      onSelectGroup: _selectGroup,
      onSelectWorld: (w) => rebuildState(() => _applyWorldSelection(w)),
    );
  }

  // Step 1 — name, summary, tags.
  Widget _detailsStep() {
    return ListView(
      key: const ValueKey('details'),
      padding: const EdgeInsets.all(24),
      children: [
        _label('Display name on The Stoop'),
        TextField(
          controller: _name,
          onChanged: (_) => rebuildState(() {}),
          style: TextStyle(color: stoopCream(context)),
          decoration: _input('Name shown on The Stoop'),
        ),
        const SizedBox(height: 8),
        // Unmissable: this box is the LISTING title, not the chat name.
        // {{char}} keeps mapping to the card's own name, which never changes
        // here — so "Misty Meadows, Misguided Meteorologist" is safe.
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: stoopAmberSoft(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.stoopAmber.withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: stoopAmberText(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selected != null
                      ? 'This is the display name for the listing only — not '
                            'the chat name. In chat, {{char}} still maps to '
                            '“${_selected!.name}”, so replies keep calling '
                            'them “${_selected!.name}” no matter what you '
                            'title the post.'
                      : 'This is the display name for the listing only — in '
                            'chat, everyone keeps their own name no matter '
                            'what you title the post.',
                  style: TextStyle(
                    color: stoopCream2(context),
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _label('Short summary'),
        TextField(
          controller: _summary,
          maxLines: 3,
          maxLength: 280,
          onChanged: (_) => rebuildState(() {}),
          style: TextStyle(color: stoopCream(context)),
          decoration: _input('A one-line hook shown on the card'),
        ),
        const SizedBox(height: 18),
        _label('Original creator (optional)'),
        TextField(
          controller: _originalCreator,
          maxLength: 120,
          onChanged: (_) => rebuildState(() {}),
          style: TextStyle(color: stoopCream(context)),
          decoration: _input('Leave blank if this is your own work').copyWith(
            counterText: '',
            helperText:
                'Sharing someone else’s character? Credit them here — the '
                'card will show “created by …”. The AUP requires this for '
                'reposts; they don’t need a Stoop account.',
            helperMaxLines: 3,
            helperStyle: TextStyle(color: stoopMute(context), fontSize: 12),
          ),
        ),
        const SizedBox(height: 8),
        StoopTagSelector(
          pool: _tagPool,
          selected: _tags,
          max: _StoopUploadPageState._maxTags,
          controller: _tagInput,
          decorate: _input,
          onToggle: (t) => rebuildState(() {
            if (_tags.contains(t)) {
              _tags.remove(t);
            } else if (_tags.length < _StoopUploadPageState._maxTags) {
              _tags.add(t);
            }
          }),
          onAdd: (raw) => rebuildState(() {
            final tag = raw.trim();
            if (tag.isEmpty) return;
            final lower = tag.toLowerCase();
            // Reuse an existing pool entry that differs only by case so
            // "Potato" and "potato" collapse to one pill (the backend dedupes
            // the same way), then select it.
            var canonical = tag;
            for (final t in _tagPool) {
              if (t.toLowerCase() == lower) {
                canonical = t;
                break;
              }
            }
            if (!_tagPool.contains(canonical)) _tagPool.add(canonical);
            final alreadySelected = _tags.any((t) => t.toLowerCase() == lower);
            if (!alreadySelected &&
                _tags.length < _StoopUploadPageState._maxTags) {
              _tags.add(canonical);
            }
          }),
        ),
      ],
    );
  }

  // Step 2 — NSFW flag + the character-agency acknowledgement + completeness.
  Widget _contentStep() {
    final completeness = _selectedCompleteness();
    return ListView(
      key: const ValueKey('content'),
      padding: const EdgeInsets.all(24),
      children: [
        if (completeness != null) ...[
          StoopCompletenessPanel(completeness: completeness),
          const SizedBox(height: 16),
        ],
        if (_forcedAdult) ...[
          const StoopAdultLockBanner(),
          const SizedBox(height: 16),
        ],
        StoopAdultSwitch(
          key: const Key('stoop-adult-switch'),
          value: _adult.value,
          locked: _forcedAdult,
          pending: _castPending,
          onChanged: (v) => rebuildState(() => _adult.setByAuthor(v)),
        ),
        const SizedBox(height: 12),
        StoopCommentsSwitch(
          key: const Key('stoop-comments-opt-in'),
          value: _commentsEnabled,
          onChanged: (v) => rebuildState(() => _commentsEnabled = v),
        ),
        const SizedBox(height: 20),
        StoopStandardsCard(
          footer: CheckboxListTile(
            value: _standardsAck,
            onChanged: (v) => rebuildState(() => _standardsAck = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: AppColors.stoopAmber,
            checkColor: AppColors.stoopAmberInk,
            title: Text(
              'This card meets the Stoop content standards',
              style: TextStyle(
                color: stoopCream(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'I confirm this card meets every standard above — and complies '
              'with The Stoop Acceptable Use Policy.',
              style: TextStyle(color: stoopCream2(context)),
            ),
          ),
        ),
      ],
    );
  }

  // Step 3 — review + publish.
  Widget _reviewStep() {
    final world = _selectedWorld;
    final isGroup = _selectedGroup != null;
    final preview = world != null
        ? stoopWorldCoverPreview(
            context,
            coverBytes: decodeWorldCoverBytes(world.coverImage),
          )
        : isGroup
        ? Container(
            width: 96,
            height: 96,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: stoopTealSoft(context),
              borderRadius: BorderRadius.circular(12),
            ),
            child: StoopGroupMontage(group: _selectedGroup!),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_selected!.imagePath!),
              width: 96,
              height: 96,
              fit: BoxFit.cover,
            ),
          );
    return ListView(
      key: const ValueKey('review'),
      padding: const EdgeInsets.all(24),
      children: [
        if (_selectedCompleteness() != null) ...[
          StoopCompletenessPanel(completeness: _selectedCompleteness()!),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            preview,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _name.text.trim(),
                    style: stoopDisplay(context, size: 21),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _summary.text.trim(),
                    style: TextStyle(color: stoopCream2(context)),
                  ),
                  if (_originalCreator.text.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'created by ${_originalCreator.text.trim()}',
                      style: TextStyle(
                        color: stoopFaint(context),
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  if (_adult.value) ...[
                    const SizedBox(height: 8),
                    const StoopBadge(StoopBadgeKind.nsfw),
                  ],
                ],
              ),
            ),
          ],
        ),
        // Last surface before Submit — say why that badge is there.
        if (_forcedAdult) ...[
          const SizedBox(height: 18),
          const StoopAdultLockBanner(),
        ],
        const SizedBox(height: 18),
        if (_tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in _tags)
                Text('#$t', style: TextStyle(color: stoopTealText(context))),
            ],
          ),
        const SizedBox(height: 20),
        Text(
          'Your submission will be reviewed by a moderator before it appears '
          'on The Stoop. You’ll get a message in the app when it’s approved or '
          'if changes are needed.',
          style: TextStyle(color: stoopMute(context), height: 1.5),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: TextStyle(color: stoopEmberText(context))),
        ],
      ],
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: TextStyle(
        color: stoopCream2(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}
