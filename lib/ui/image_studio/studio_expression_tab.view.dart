// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of 'studio_expression_tab.dart';

extension _StudioExpressionTabView on StudioExpressionTabState {
  Widget _buildWorkspace(BuildContext context) {
    final repository = context.watch<CharacterRepository?>();
    final settings = context.watch<StorageService>().imageGenSettings;
    final imageGen = context.watch<ImageGenService>();
    final backend = settings.imageGenBackend;
    final edit =
        backend == 'comfyui' ||
        backend == 'remote' ||
        ImageReferenceResolver.packEditMode(settings);
    final prepared = _prepared;
    final card = _character;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OtherExpressionPack(
          owned: (run) => _packKey.currentState?.owns(run) ?? false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Expressions',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary(context),
                  ),
                ),
              ),
              if (hasPack)
                Tooltip(
                  message:
                      'Clear pack results and unlock the target, prompt, and source. Imported expressions stay in the library.',
                  child: TextButton(
                    onPressed: _loading || _crafting ? null : _newPack,
                    child: const Text('Reset pack'),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 700;
              final draft = SingleChildScrollView(
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
                              DropdownMenuItem(
                                value: c.dbId,
                                child: Text(c.name),
                              ),
                        ],
                        onChanged: _frozen || _loading || _crafting
                            ? null
                            : (id) {
                                final chosen = repository.characters
                                    .where((c) => c.dbId == id)
                                    .firstOrNull;
                                if (chosen != null) {
                                  _selectCharacter(chosen);
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
                        controller: _description,
                        enabled: !_frozen && !_crafting,
                        minLines: 2,
                        maxLines: 4,
                        onChanged: (_) =>
                            _setWorkspaceState(() => _draftTouched = true),
                        decoration: const InputDecoration(
                          labelText: 'Image prompt',
                          hintText:
                              'Describe the character, appearance, and framing',
                        ),
                      ),
                      TextButton(
                        onPressed: _frozen || _crafting || card == null
                            ? null
                            : _writePrompt,
                        child: Text(
                          _crafting ? 'Writing prompt…' : 'Write it for me',
                        ),
                      ),
                      const Text(
                        'Leave blank to prepare an image prompt automatically when starting.',
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text('Source: $_sourceCaption'),
                    if (_source != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Image.memory(
                          _source!,
                          height: 110,
                          fit: BoxFit.contain,
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton(
                          onPressed: _frozen || _loading || card == null
                              ? null
                              : () {
                                  _setWorkspaceState(
                                    () => _sourceCaption = 'Character portrait',
                                  );
                                  _loadPortrait();
                                },
                          child: const Text('Use character portrait'),
                        ),
                        TextButton(
                          onPressed: _frozen || _loading ? null : _upload,
                          child: const Text('Upload source'),
                        ),
                        TextButton(
                          onPressed:
                              _frozen ||
                                  _loading ||
                                  widget.lastStudioImage == null
                              ? null
                              : () {
                                  _setWorkspaceState(
                                    () =>
                                        _sourceCaption = 'Last Studio picture',
                                  );
                                  _prepareSource(widget.lastStudioImage);
                                },
                          child: const Text('Use last Studio picture'),
                        ),
                      ],
                    ),
                    if (_frozen)
                      const Text(
                        'Target, prompt, and source are fixed for this pack. Reset pack clears its results and unlocks these fields. Use Start to generate again.',
                      ),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error.isNotEmpty) Text(_error),
                    const SizedBox(height: 12),
                    Text(
                      edit
                          ? 'Pack uses the Edit model and workflow.'
                          : kStudioCreatePack,
                    ),
                    const SizedBox(height: 8),
                    StudioDesk(editMode: edit, showGenerate: false),
                  ],
                ),
              );
              final pack =
                  prepared == null || card?.dbId == null || repository == null
                  ? const Center(
                      child: Text(
                        'Choose a character and source portrait to set up expressions.',
                      ),
                    )
                  : ExpressionPackDialog.workspace(
                      key: _packKey,
                      characterDbId: card!.dbId!,
                      characterName: card.name,
                      repository: repository,
                      storage: context.read<StorageService>(),
                      imageGen: imageGen,
                      baseImage: prepared.bytes,
                      baseWidth: prepared.width,
                      baseHeight: prepared.height,
                      basePrompt: _description.text.trim(),
                      preparePrompt: () => _craftPrompt(automatic: true),
                      preparingPrompt: _crafting,
                      negativePrompt: settings.imageGenNegativePrompt,
                      existingEmotions: _existing,
                      note: prepared.note,
                      onSessionChanged: (hasSession) {
                        _setWorkspaceState(() => _frozen = hasSession);
                        widget.onPackChanged?.call();
                      },
                      onImported: () => widget.onImported?.call(card.dbId!),
                      onDiscard: _newPack,
                    );
              if (wide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: draft),
                    Expanded(flex: 2, child: pack),
                  ],
                );
              }
              return SingleChildScrollView(
                child: Column(
                  children: [
                    SizedBox(height: 440, child: draft),
                    SizedBox(height: 580, child: pack),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
