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

import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import '../studio_widgets.dart';

/// The Expressions tab's draft column: import target, image prompt, source
/// portrait and the desk. The tab owns every value; this only shows them and
/// reports taps.
class ExpressionDraftPane extends StatelessWidget {
  const ExpressionDraftPane({
    super.key,
    required this.repository,
    required this.card,
    required this.edit,
    required this.frozen,
    required this.loading,
    required this.crafting,
    required this.description,
    required this.sourceCaption,
    required this.source,
    required this.lastStudioImage,
    required this.error,
    required this.onSelectCharacter,
    required this.onDraftEdited,
    required this.onWritePrompt,
    required this.onUsePortrait,
    required this.onUpload,
    required this.onUseLast,
  });

  final CharacterRepository? repository;
  final CharacterCard? card;
  final bool edit;
  final bool frozen;
  final bool loading;
  final bool crafting;
  final TextEditingController description;
  final String sourceCaption;
  final Uint8List? source;
  final Uint8List? lastStudioImage;
  final String error;
  final ValueChanged<CharacterCard> onSelectCharacter;
  final VoidCallback onDraftEdited;
  final VoidCallback onWritePrompt;
  final VoidCallback onUsePortrait;
  final VoidCallback onUpload;
  final VoidCallback onUseLast;

  @override
  Widget build(BuildContext context) {
    final repository = this.repository;
    final card = this.card;
    return SingleChildScrollView(
      primary: false,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (repository == null)
            const Text(
              'Character library is unavailable. Open Studio from a library character to build a pack.',
            )
          else if (repository.characters.isEmpty)
            const Text(
              'Your character library is empty. Add a character before building a pack.',
            )
          else
            DropdownButtonFormField<String>(
              key: const Key('expression-character'),
              initialValue: card?.dbId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Import expressions into',
              ),
              items: [
                for (final c in repository.characters)
                  if (c.dbId != null)
                    DropdownMenuItem(value: c.dbId, child: Text(c.name)),
              ],
              onChanged: frozen || loading || crafting
                  ? null
                  : (id) {
                      final chosen = repository.characters
                          .where((c) => c.dbId == id)
                          .firstOrNull;
                      if (chosen != null) {
                        onSelectCharacter(chosen);
                      }
                    },
            ),
          const SizedBox(height: 12),
          if (edit)
            const Text(
              'Each expression supplies its own edit instruction. No base prompt is needed.',
            )
          else ...[
            TextField(
              key: const Key('expression-description'),
              controller: description,
              enabled: !frozen && !crafting,
              minLines: 2,
              maxLines: 4,
              onChanged: (_) => onDraftEdited(),
              decoration: const InputDecoration(
                labelText: 'Image prompt',
                hintText: 'Describe the character, appearance, and framing',
              ),
            ),
            TextButton(
              onPressed: frozen || crafting || card == null
                  ? null
                  : onWritePrompt,
              child: Text(crafting ? 'Writing prompt…' : 'Write it for me'),
            ),
            const Text(
              'Leave blank to prepare an image prompt automatically when starting.',
            ),
          ],
          const SizedBox(height: 12),
          Text('Source: $sourceCaption'),
          if (source != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Image.memory(source!, height: 110, fit: BoxFit.contain),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: frozen || loading || card == null
                    ? null
                    : onUsePortrait,
                child: const Text('Use character portrait'),
              ),
              TextButton(
                onPressed: frozen || loading ? null : onUpload,
                child: const Text('Upload source'),
              ),
              TextButton(
                onPressed: frozen || loading || lastStudioImage == null
                    ? null
                    : onUseLast,
                child: const Text('Use last Studio picture'),
              ),
            ],
          ),
          if (frozen)
            const Text(
              'Target, prompt, and source are fixed for this pack. Reset pack clears its results and unlocks these fields. Use Start to generate again.',
            ),
          if (loading) const LinearProgressIndicator(),
          if (error.isNotEmpty) Text(error),
          const SizedBox(height: 12),
          Text(
            edit ? 'Pack uses the Edit model and workflow.' : kStudioCreatePack,
          ),
          const SizedBox(height: 8),
          StudioDesk(editMode: edit, showGenerate: false),
        ],
      ),
    );
  }
}
