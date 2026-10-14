// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'package:front_porch_ai/ui/image_studio/studio_widgets.dart';

class ImageBatchPrepare extends StatefulWidget {
  const ImageBatchPrepare({
    super.key,
    required this.queue,
    required this.repository,
    required this.busy,
    required this.onAction,
    required this.onPrepared,
  });
  final VoidCallback onPrepared;
  final ImageBatchService queue;
  final CharacterRepository repository;
  final bool busy;
  final Future<void> Function(Future<void> Function()) onAction;
  @override
  State<ImageBatchPrepare> createState() => _ImageBatchPrepareState();
}

class _ImageBatchPrepareState extends State<ImageBatchPrepare> {
  final _selected = <String>{};
  final _prompt = TextEditingController();
  String _kind = 'additional';
  String _search = '';
  bool _edit = false;
  bool _missing = true;
  bool _fullSet = false;
  ExpressionPromptRules? _rules;

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  void _update(VoidCallback change) {
    if (mounted) setState(change);
  }

  Future<void> _action(Future<void> Function() action) =>
      widget.onAction(action);
  @override
  Widget build(BuildContext context) =>
      _prepare(widget.queue, widget.repository, widget.busy);

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
      Text(
        'Add work across characters',
        style: Theme.of(context).textTheme.titleLarge,
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
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: busy
                ? null
                : () => _update(() {
                    _selected.addAll(
                      repo.characters
                          .where(
                            (c) =>
                                c.dbId != null &&
                                '${c.name} ${_folderPath(c.imagePath)}'
                                    .toLowerCase()
                                    .contains(_search),
                          )
                          .map((c) => c.dbId!),
                    );
                  }),
            child: const Text('Select visible'),
          ),
          TextButton(
            onPressed: busy ? null : () => _update(_selected.clear),
            child: const Text('Clear selection'),
          ),
        ],
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
          subtitle: Text(
            '${_folderPath(card.imagePath)}${repo.characters.where((other) => other.name == card.name).length > 1 ? ' · ${card.dbId!.substring(0, 8)}' : ''}',
          ),
          secondary: card.imagePath == null
              ? const Icon(Icons.person)
              : ClipOval(
                  child: Image.file(
                    queue.storage.resolveCharacterImage(card.imagePath!),
                    width: 40,
                    height: 40,
                    cacheWidth: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.person),
                  ),
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
                  widget.onPrepared();
                }
              }),
        child: Text(
          'Prepare for ${_selected.length} ${_selected.length == 1 ? 'character' : 'characters'}',
        ),
      ),
    ],
  );
}
