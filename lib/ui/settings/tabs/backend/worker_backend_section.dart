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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

/// Side jobs sit below the complete Chat speech stack. Same-as-chat
/// (empty worker type) shows no second URL/key/model.
class WorkerBackendSection extends StatefulWidget {
  const WorkerBackendSection({
    super.key,
    this.kcppsPresets = const [],
    this.compact = false,
  });

  final List<File> kcppsPresets;

  /// In-chat Model Settings: tighter top spacing, same storage and chrome.
  final bool compact;

  @override
  State<WorkerBackendSection> createState() => _WorkerBackendSectionState();
}

class _WorkerBackendSectionState extends State<WorkerBackendSection> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  List<RemoteModelInfo> _models = const [];
  bool _fetching = false;
  bool _pickingDifferent = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<StorageService>();
    _url = TextEditingController(text: s.workerRemoteApiUrl);
    _key = TextEditingController();
    _pickingDifferent = !workerBackendIsOff(s.workerBackendType);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final llm = context.watch<LLMProvider>();
    // Dialog goldens / interaction pumps omit BackendManager. Same floor
    // as ModelManager below — Intel Mac is the only read.
    var intelMac = false;
    try {
      intelMac = Provider.of<BackendManager>(context).isIntelMac;
    } on ProviderNotFoundException {
      intelMac = false;
    }
    final theme = Theme.of(context);
    final muted = AppColors.textTertiary(context);
    final off = workerBackendIsOff(storage.workerBackendType);
    // This package's Provider has no maybeOf. Section tests omit ModelManager.
    List<FileSystemEntity> koboldModels = const [];
    if (!off && storage.workerBackendType == 'kobold') {
      try {
        koboldModels = Provider.of<ModelManager>(context).models;
      } on ProviderNotFoundException {
        koboldModels = const [];
      }
    }
    final different = !off || _pickingDifferent;
    final kind = off
        ? RemoteProviderKind.custom
        : resolveRemoteProviderKind(
            backendType: storage.workerBackendType,
            url: storage.workerRemoteApiUrl,
          );
    final sameHost = workerHostMatchesChat(
      mouthType: storage.backendType,
      mouthUrl: storage.remoteApiUrl,
      workerType: storage.workerBackendType,
      workerUrl: storage.workerRemoteApiUrl,
    );
    final workerUrl = resolvedLaneApiUrl(
      storage.workerBackendType,
      storage.workerRemoteApiUrl,
    );
    final vaultHasKey = storage.remoteApiKeyFor(workerUrl).isNotEmpty;
    final showUrl =
        different && !off && !sameHost && remoteProviderShowsUrlField(kind);
    final showKey =
        different &&
        !off &&
        workerShowsApiKeyField(
          sameHost: sameHost,
          workerKind: kind,
          vaultHasKey: vaultHasKey,
        );
    final showSavedKeyHint =
        different &&
        !off &&
        !sameHost &&
        remoteProviderNeedsApiKey(kind) &&
        vaultHasKey;
    final showModel =
        different &&
        !off &&
        (storage.workerBackendType == 'openRouter' ||
            storage.workerBackendType == 'omlx');

    return Column(
      key: const Key('side-jobs-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: widget.compact ? 16 : 28),
        Divider(color: AppColors.borderOf(context)),
        SizedBox(height: widget.compact ? 12 : 16),
        const SectionHeader('Realism evals'),
        const SizedBox(height: 8),
        Text(
          widget.compact
              ? 'Feelings, wiki/web, journal, and growth can use another '
                    'host. Chat speech stays above.'
              : 'Feelings, wiki/web, journal, growth can use another host. '
                    'Chat speech stays above. Two local engines take turns on '
                    'the GPU when this app can unload one model before the '
                    'other runs.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 10),
        if (different)
          WorkerLaneStatusBanners(
            refusedDualLocal: llm.workerRefusedDualLocal,
            unreadyMessage: llm.workerUnreadyMessage,
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SideJobsModeToggle(
                different: different,
                onSame: () async {
                  await applyWorkerProvider(kind: null, storage: storage);
                  if (!context.mounted) return;
                  setState(() {
                    _pickingDifferent = false;
                    _url.text = storage.workerRemoteApiUrl;
                    _models = const [];
                  });
                },
                onDifferent: () => setState(() => _pickingDifferent = true),
              ),
              if (!different) ...[
                const SizedBox(height: 10),
                Text(
                  'Realism evals use the chat host above.',
                  key: const Key('side-jobs-same-host-status'),
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ] else ...[
                const SizedBox(height: 12),
                RemoteProviderBar(
                  selected: kind,
                  noneSelected: off,
                  showOmlx: Platform.isMacOS,
                  koboldEnabled: !intelMac,
                  onSelected: (next) async {
                    await applyWorkerProvider(
                      kind: next,
                      storage: storage,
                      urlController: _url,
                    );
                    if (!context.mounted) return;
                    setState(() => _models = const []);
                  },
                ),
                if (off)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Pick a host for Realism evals. Chat speech stays above.',
                      style: theme.textTheme.bodySmall?.copyWith(color: muted),
                    ),
                  )
                else if (sameHost) ...[
                  const SizedBox(height: 10),
                  Text(
                    'Realism evals use the chat host above. Pick a model only.',
                    key: const Key('side-jobs-same-host-status'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                if (showUrl) ...[
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('side-jobs-worker-url'),
                    controller: _url,
                    decoration: const InputDecoration(
                      labelText: 'API URL',
                      hintText: 'https://your-server.example/v1',
                    ),
                    onSubmitted: (v) => storage.setWorkerRemoteApiUrl(v.trim()),
                    onTapOutside: (_) =>
                        storage.setWorkerRemoteApiUrl(_url.text.trim()),
                  ),
                ],
                if (showModel) ...[
                  const SizedBox(height: 12),
                  RemoteModelPickerField(
                    key: const Key('side-jobs-model-picker'),
                    availableModels: _models,
                    selectedId: storage.workerRemoteModelName,
                    fetching: _fetching,
                    dialogTitle: 'Realism evals model',
                    onRefresh: () async {
                      setState(() => _fetching = true);
                      try {
                        if (_url.text.trim().isNotEmpty) {
                          await storage.setWorkerRemoteApiUrl(_url.text.trim());
                        }
                        final list = await llm.workerRemoteService
                            .fetchAvailableModels();
                        if (!mounted) return;
                        setState(() => _models = list);
                      } finally {
                        if (mounted) setState(() => _fetching = false);
                      }
                    },
                    onSelected: (m) {
                      storage.setWorkerRemoteModelName(m.id);
                    },
                    onTyped: storage.setWorkerRemoteModelName,
                  ),
                ],
                if (showKey) ...[
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('side-jobs-worker-key'),
                    controller: _key,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API key',
                      hintText: 'Key for this host',
                    ),
                    onSubmitted: (v) {
                      if (v.trim().isEmpty) return;
                      storage.setRemoteApiKeyFor(workerUrl, v.trim());
                      _key.clear();
                    },
                  ),
                ],
                if (showSavedKeyHint) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Using the saved key for this host.',
                    key: const Key('side-jobs-saved-key-hint'),
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
                if (!off && storage.workerBackendType == 'kobold') ...[
                  const SizedBox(height: 12),
                  WorkerKoboldModelPicker(
                    selectedPath: storage.workerKoboldModelPath,
                    mouthPath: storage.lastUsedModelPath,
                    models: koboldModels,
                    onChanged: storage.setWorkerKoboldModelPath,
                  ),
                  const SizedBox(height: 12),
                  WorkerKoboldKcppsPicker(
                    selectedPath: storage.workerKoboldKcppsPath,
                    mouthPath: storage.activeKcppsPath,
                    modelsMatch:
                        normalizeLocalModelPath(
                          storage.resolvedWorkerKoboldModelPath(),
                        ) ==
                        normalizeLocalModelPath(
                          storage.lastUsedModelPath ?? '',
                        ),
                    presets: widget.kcppsPresets,
                    onChanged: storage.setWorkerKoboldKcppsPath,
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SideJobsModeToggle extends StatelessWidget {
  const _SideJobsModeToggle({
    required this.different,
    required this.onSame,
    required this.onDifferent,
  });

  final bool different;
  final VoidCallback onSame;
  final VoidCallback onDifferent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ModePill(
            key: const Key('side-jobs-same-as-chat'),
            label: 'Same as chat',
            selected: !different,
            onTap: onSame,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ModePill(
            key: const Key('side-jobs-different-host'),
            label: 'Different host…',
            selected: different,
            onTap: onDifferent,
          ),
        ),
      ],
    );
  }
}

class _ModePill extends StatelessWidget {
  const _ModePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.porchAmberOf(context);
    return Material(
      color: selected ? accent : AppColors.surfaceContainerOf(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? accent : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppColors.onChaosAccent
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dual-local refuse wins over an unready host. Empty = no banner.
class WorkerLaneStatusBanners extends StatelessWidget {
  const WorkerLaneStatusBanners({
    super.key,
    required this.refusedDualLocal,
    this.unreadyMessage,
  });

  final bool refusedDualLocal;
  final String? unreadyMessage;

  @override
  Widget build(BuildContext context) {
    final text = refusedDualLocal
        ? kWorkerDualLocalMessage
        : (unreadyMessage ?? '');
    if (text.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        WorkerLaneWarnBanner(
          text,
          key: refusedDualLocal
              ? const Key('worker-dual-local-banner')
              : const Key('worker-unready-banner'),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class WorkerLaneWarnBanner extends StatelessWidget {
  const WorkerLaneWarnBanner(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final warn = AppColors.taskAccentOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: warn),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: warn)),
          ),
        ],
      ),
    );
  }
}
