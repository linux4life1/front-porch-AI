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

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/story_setup/setup_widgets.dart';
import 'package:front_porch_ai/ui/story_studio/story_studio.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The story-only model picker (sketch L): Same as chat, Worker model, or
/// any host + model. Never shows a chat setting. Resolves to the choice or
/// null on cancel.
Future<StoryLaneChoice?> showModelPickerSheet(
  BuildContext context, {
  required String job,
  required StoryLaneChoice current,
}) => showDialog<StoryLaneChoice>(
  context: context,
  builder: (_) => _ModelPickerSheet(job: job, initial: current.copy()),
);

class _ModelPickerSheet extends StatefulWidget {
  final String job;
  final StoryLaneChoice initial;

  const _ModelPickerSheet({required this.job, required this.initial});

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  late StoryLaneChoice _choice = widget.initial;
  late final Map<String, dynamic> _options;
  late final TextEditingController _url;
  final _key = TextEditingController();
  List<RemoteModelInfo> _models = const [];
  bool _fetching = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _options = storyLaneOptionsFor(
      context.read<StorageService>(),
      context.read<LLMProvider>(),
    );
    _url = TextEditingController(text: _choice.apiUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _hosts =>
      (_options['hosts'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic>? get _host {
    if (_choice.lane != StoryModelLane.host) return null;
    for (final h in _hosts) {
      if (h['type'] == _choice.backendType &&
          (h['type'] != 'openRouter' || _kindMatches(h))) {
        return h;
      }
    }
    return null;
  }

  bool _kindMatches(Map<String, dynamic> h) {
    final url = _choice.apiUrl.trim();
    if (h['kind'] == 'custom') {
      return _hosts.every((o) => o['kind'] == 'custom' || o['url'] != url);
    }
    return h['url'] == url;
  }

  void _pickHost(Map<String, dynamic> h) {
    setState(() {
      _choice
        ..lane = StoryModelLane.host
        ..backendType = h['type'] as String
        ..apiUrl = h['kind'] == 'custom' ? '' : h['url'] as String
        ..model = ''
        ..kcpps = '';
      _url.text = _choice.apiUrl;
      _models = const [];
      _note = null;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _fetching = true;
      _note = null;
    });
    try {
      final storage = context.read<StorageService>();
      final llm = context.read<LLMProvider>();
      _choice.apiUrl = _url.text.trim();
      final resolved = storyLaneResolvedUrl(
        _choice.backendType,
        _choice.apiUrl,
      );
      if (_key.text.trim().isNotEmpty) {
        await storage.setRemoteApiKeyFor(resolved, _key.text.trim());
        _key.clear();
      }
      final list = await llm.openRouterService.fetchAvailableModels(
        apiUrl: resolved,
        apiKey: storage.remoteApiKeyFor(resolved),
      );
      if (!mounted) return;
      setState(() {
        _models = list;
        _note = list.isEmpty
            ? 'This host answered with no models. Check the URL and key.'
            : '${list.length} models from this host.';
      });
    } catch (e) {
      if (mounted) setState(() => _note = 'Could not reach this host: $e');
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _pickRemoteModel() async {
    if (_models.isEmpty) await _refresh();
    if (!mounted || _models.isEmpty) return;
    final picked = await showStoryDialog<String>(
      context,
      title: 'Model',
      width: 460,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in _models)
            InkWell(
              key: ValueKey('story-model-${m.id}'),
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.pop(context, m.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.id,
                        style: StudioType.mono(
                          context,
                          color: StudioColors.inkOf(context),
                        ),
                      ),
                    ),
                    if (m.name.isNotEmpty && m.name != m.id)
                      Text(
                        m.name,
                        style: StudioType.ui(
                          context,
                          size: 12,
                          color: StudioColors.mutedOf(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (picked != null) setState(() => _choice.model = picked);
  }

  Future<void> _pickFile(
    String title,
    List<Map<String, String>> files,
    ValueChanged<String> onPick,
  ) async {
    final picked = await showStoryDialog<String>(
      context,
      title: title,
      width: 460,
      body: files.isEmpty
          ? Text(
              'Nothing found in the models folder.',
              style: StudioType.ui(
                context,
                size: 12.5,
                color: StudioColors.mutedOf(context),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in files)
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => Navigator.pop(context, f['path']),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              f['name'] ?? '',
                              style: StudioType.ui(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
      actions: (ctx) => [
        StoryButton.ghost('Cancel', onPressed: () => Navigator.pop(ctx)),
      ],
    );
    if (picked != null) setState(() => onPick(picked));
  }

  @override
  Widget build(BuildContext context) {
    final chat = _options['chat'] as Map<String, dynamic>;
    final worker = _options['worker'] as Map<String, dynamic>?;
    final host = _host;
    final isHost = _choice.lane == StoryModelLane.host;
    final muted = StudioColors.mutedOf(context);
    return StudioTheme(
      child: Dialog(
        backgroundColor: StudioColors.cardOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: StudioColors.lineOf(context)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${widget.job} model',
                        style: StudioType.ui(
                          context,
                          size: 15,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    StoryIconButton(
                      Icons.close,
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StoryRadioRow(
                          key: const ValueKey('story-lane-chat'),
                          selected: _choice.lane == StoryModelLane.main,
                          onTap: () =>
                              setState(() => _choice = StoryLaneChoice.chat()),
                          title: 'Same as chat',
                          detail: chat['detail'] as String,
                        ),
                        if (worker != null)
                          StoryRadioRow(
                            key: const ValueKey('story-lane-worker'),
                            selected: _choice.lane == StoryModelLane.worker,
                            onTap: () => setState(
                              () => _choice = StoryLaneChoice.worker(),
                            ),
                            title: 'Worker model',
                            detail: worker['detail'] as String,
                          ),
                        StoryRadioRow(
                          key: const ValueKey('story-lane-host'),
                          selected: isHost,
                          onTap: () => _pickHost(_hosts.first),
                          title: 'Another host',
                        ),
                        if (isHost)
                          Padding(
                            padding: const EdgeInsets.only(left: 26),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final h in _hosts)
                                      StoryChip(
                                        h['label'] as String,
                                        key: ValueKey(
                                          'story-host-${h['kind']}',
                                        ),
                                        selected: identical(h, host),
                                        onTap: () => _pickHost(h),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (host != null) ..._hostFields(host, muted),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (isHost && _choice.backendType != 'kobold')
                      StoryButton.ghost(
                        'Test',
                        onPressed: _fetching ? null : _refresh,
                      ),
                    const Spacer(),
                    StoryButton.ghost(
                      'Cancel',
                      onPressed: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 8),
                    StoryButton.primary(
                      'Use this model',
                      key: const ValueKey('story-lane-use'),
                      onPressed: isHost && _choice.model.trim().isEmpty
                          ? null
                          : () => Navigator.pop(context, _choice),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _hostFields(Map<String, dynamic> host, Color muted) {
    final kobold = host['type'] == 'kobold';
    final needsKey = host['needsKey'] == true && host['hasKey'] != true;
    final local = host['local'] == true;
    final note = _note;
    return [
      if (host['kind'] == 'custom') ...[
        const SetupNote('API URL'),
        const SizedBox(height: 4),
        StoryField(
          controller: _url,
          hint: 'https://your-server.example/v1',
          onChanged: (v) => _choice.apiUrl = v.trim(),
        ),
        const SizedBox(height: 8),
      ],
      if (kobold) ...[
        const SetupNote('Model file'),
        const SizedBox(height: 4),
        StoryPickField(
          value: _choice.model.isEmpty ? '' : path.basename(_choice.model),
          placeholder: 'Choose a .gguf',
          onTap: () => _pickFile(
            'Model file',
            (_options['koboldModels'] as List).cast<Map<String, String>>(),
            (p) => _choice.model = p,
          ),
        ),
        const SizedBox(height: 8),
        const SetupNote('Launch preset'),
        const SizedBox(height: 4),
        StoryPickField(
          value: _choice.kcpps.isEmpty ? '' : path.basename(_choice.kcpps),
          placeholder: 'Same as chat',
          onTap: () => _pickFile(
            'Launch preset',
            (_options['kcpps'] as List).cast<Map<String, String>>(),
            (p) => _choice.kcpps = p,
          ),
        ),
      ] else ...[
        Row(
          children: [
            const Expanded(child: SetupNote('Model')),
            StoryButton.ghost(
              _fetching ? 'Fetching…' : 'Refresh list',
              icon: Icons.refresh,
              onPressed: _fetching ? null : _refresh,
            ),
          ],
        ),
        const SizedBox(height: 4),
        StoryPickField(
          key: const ValueKey('story-host-model'),
          value: _choice.model,
          placeholder: 'Choose a model',
          onTap: _pickRemoteModel,
        ),
        if (needsKey) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: true,
            style: StudioType.ui(context, size: 13),
            decoration: const InputDecoration(
              hintText: 'API key for this host',
            ),
          ),
        ] else if (host['needsKey'] == true) ...[
          const SizedBox(height: 6),
          SetupNote('Using the saved key for ${host['label']}.'),
        ],
      ],
      if (note != null) ...[const SizedBox(height: 6), SetupNote(note)],
      if (local) ...[
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const StoryChip('Swaps with the chat model', tone: 'honey'),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Each switch unloads one model and loads the other. Reviews '
                'are grouped so it happens once per stage, not once per try.',
                style: StudioType.ui(context, size: 12, color: muted),
              ),
            ),
          ],
        ),
      ],
    ];
  }
}
