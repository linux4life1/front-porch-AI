// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

part of '../image_batches_page.dart';

extension _ImageBatchPrepareView on _ImageBatchesPageState {
  String _folderPath(String? imagePath) {
    final folders = context.watch<FolderService?>();
    final folder = imagePath == null
        ? null
        : folders?.getFolderForCharacter(imagePath);
    return folder == null ? 'Library root' : folders!.getFolderPath(folder.id);
  }

  bool _configurationEdit(ImageBatchService queue) => _kind == 'expressions'
      ? ([
              'comfyui',
              'remote',
            ].contains(queue.storage.imageGenSettings.imageGenBackend) ||
            ImageReferenceResolver.packEditMode(queue.storage.imageGenSettings))
      : _edit;

  Future<void> _editRules(
    ImageBatchService queue,
    CharacterRepository repo,
  ) async {
    final settings = queue.storage.expressionSettings;
    if (!mounted) return;
    final card = repo.characters
        .where((c) => c.dbId == _selected.firstOrNull)
        .firstOrNull;
    final base = imageBatchBasePrompt(
      _prompt.text,
      card?.name ?? 'Character',
      card?.description ?? '',
    );
    final originals = {
      for (final emotion
          in _fullSet ? kFullExpressionSet : kCuratedExpressionSet)
        emotion: originalExpressionPrompt(
          emotion: emotion,
          basePrompt: base,
          editMode: _configurationEdit(queue),
        ),
    };
    final result = await showExpressionPromptRulesEditor(
      context,
      rules: _rules ?? settings.expressionPromptRules,
      globalDefaults: () => settings.expressionPromptRules,
      saveDefaults: settings.setExpressionPromptRules,
      originals: originals,
    );
    if (mounted && result != null) _update(() => _rules = result);
  }

  Widget _prepare(
    ImageBatchService queue,
    CharacterRepository repo,
    bool busy,
  ) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'Add work across characters',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: _kind,
        decoration: const InputDecoration(labelText: 'Save destination'),
        items: const [
          DropdownMenuItem(
            value: 'additional',
            child: Text('Additional portraits · character gallery'),
          ),
          DropdownMenuItem(value: 'expressions', child: Text('Expression set')),
          DropdownMenuItem(value: 'portrait', child: Text('Primary portrait')),
        ],
        onChanged: busy ? null : (v) => _update(() => _kind = v!),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _kind == 'additional'
              ? 'Additional portraits are saved to the character’s gallery. They do not replace the primary portrait or become expressions.'
              : _kind == 'expressions'
              ? 'Expression wording comes from the shared expression prompts and your rules. Character descriptions are used only for img2img.'
              : 'Primary portraits replace the character’s current portrait only after review and confirmation.',
        ),
      ),
      TextField(
        controller: _prompt,
        enabled: !busy,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          labelText: 'Prompt / instruction',
          hintText: 'Use {character} for each character’s name.',
        ),
      ),
      if (_kind != 'expressions')
        CheckboxListTile(
          value: _edit,
          onChanged: busy ? null : (v) => _update(() => _edit = v!),
          title: const Text('Edit the current character portrait'),
        ),
      if (_kind == 'expressions')
        CheckboxListTile(
          value: _missing,
          onChanged: busy ? null : (v) => _update(() => _missing = v!),
          title: const Text('Only missing expressions'),
        ),
      Text(
        'Uses shared generation settings: ${queue.snapshot()['backend']} · ${_configurationEdit(queue) ? queue.snapshot()['editModel'] : queue.snapshot()['model']}',
      ),
      const Text(
        'Source images and prompts are captured when prepared. Changing generation settings pauses older waiting work until those settings are restored.',
      ),
      if (_kind == 'expressions') ...[
        DropdownButtonFormField<bool>(
          initialValue: _fullSet,
          decoration: const InputDecoration(labelText: 'Expression set'),
          items: [
            DropdownMenuItem(
              value: false,
              child: Text('Starter (${kCuratedExpressionSet.length})'),
            ),
            DropdownMenuItem(
              value: true,
              child: Text('Full (${kFullExpressionSet.length})'),
            ),
          ],
          onChanged: busy ? null : (v) => _update(() => _fullSet = v!),
        ),
        TextButton.icon(
          onPressed: busy ? null : () => _action(() => _editRules(queue, repo)),
          icon: const Icon(Icons.tune),
          label: Text(
            _rules == null
                ? 'Prompt rules · global defaults'
                : 'Prompt rules · local override',
          ),
        ),
        if (_rules != null)
          TextButton(
            onPressed: busy ? null : () => _update(() => _rules = null),
            child: const Text('Follow global prompt rules'),
          ),
      ],
      ExpansionTile(
        title: const Text('Generation settings'),
        subtitle: Text(
          _configurationEdit(queue)
              ? 'Edit graph and model'
              : 'Create graph and model',
        ),
        children: [
          ChangeNotifierProvider<StorageService>.value(
            value: queue.storage,
            child: ChangeNotifierProvider<ImageGenService>.value(
              value: queue.image,
              child: StudioSettingsGate(
                busy: busy,
                child: StudioDesk(
                  key: ValueKey(_configurationEdit(queue)),
                  editMode: _configurationEdit(queue),
                  showGenerate: false,
                ),
              ),
            ),
          ),
        ],
      ),
      TextField(
        decoration: const InputDecoration(labelText: 'Find characters'),
        onChanged: (v) => _update(() => _search = v.toLowerCase()),
      ),
      for (final card in repo.characters.where(
        (c) =>
            c.dbId != null &&
            '${c.name} ${_folderPath(c.imagePath)}'.toLowerCase().contains(
              _search,
            ),
      ))
        CheckboxListTile(
          value: _selected.contains(card.dbId),
          title: Text(card.name),
          subtitle: Text(_folderPath(card.imagePath)),
          secondary: CircleAvatar(
            backgroundImage: card.imagePath == null
                ? null
                : ResizeImage(FileImage(File(card.imagePath!)), width: 80),
            onBackgroundImageError: card.imagePath == null ? null : (_, _) {},
            child: card.imagePath == null ? const Icon(Icons.person) : null,
          ),
          onChanged: busy
              ? null
              : (v) => _update(() {
                  if (v!) {
                    _selected.add(card.dbId!);
                  } else {
                    _selected.remove(card.dbId);
                  }
                }),
        ),
      FilledButton(
        onPressed: busy || _selected.isEmpty
            ? null
            : () => _action(() async {
                await queue.prepare(
                  repository: repo,
                  characterIds: _selected.toList(),
                  kind: _kind,
                  prompt: _prompt.text,
                  edit: _edit,
                  missingOnly: _missing,
                  fullSet: _fullSet,
                  promptRules: _rules,
                );
                if (mounted) {
                  _update(() {
                    _tab = 1;
                    _error = null;
                  });
                }
              }),
        child: Text('Prepare for ${_selected.length} characters'),
      ),
    ],
  );
}
