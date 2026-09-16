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
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';

/// Side-lane host. Same picker families as the chat backend; Off keeps
/// today's single-backend behavior.
class WorkerBackendSection extends StatefulWidget {
  const WorkerBackendSection({super.key});

  @override
  State<WorkerBackendSection> createState() => _WorkerBackendSectionState();
}

class _WorkerBackendSectionState extends State<WorkerBackendSection> {
  late final TextEditingController _url;
  late final TextEditingController _model;
  late final TextEditingController _key;
  List<RemoteModelInfo> _models = const [];
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    final s = context.read<StorageService>();
    _url = TextEditingController(text: s.workerRemoteApiUrl);
    _model = TextEditingController(text: s.workerRemoteModelName);
    _key = TextEditingController();
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final llm = context.watch<LLMProvider>();
    final backendManager = context.watch<BackendManager>();
    final theme = Theme.of(context);
    final muted = AppColors.textTertiary(context);
    final off = workerBackendIsOff(storage.workerBackendType);
    final kind = off
        ? RemoteProviderKind.custom
        : resolveRemoteProviderKind(
            backendType: storage.workerBackendType,
            url: storage.workerRemoteApiUrl,
          );
    final showUrl = !off && remoteProviderShowsUrlField(kind);
    final needsKey = !off && remoteProviderNeedsApiKey(kind);
    final showModel =
        !off &&
        (storage.workerBackendType == 'openRouter' ||
            storage.workerBackendType == 'omlx');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('Worker backend'),
        const SizedBox(height: 8),
        Text(
          'Side jobs (feelings, wiki/web lookup, journal, growth) can use a '
          'different host so chat speech stays on your main model. Leave this '
          'off to keep everything on the backend above. Two cloud hosts, or '
          'one cloud and one local, are fine. Two local engines take turns '
          'on the GPU when this app can unload one model before the other '
          'runs. A local host with no unload path stays on chat speech.',
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 10),
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
              Row(
                children: [
                  Expanded(
                    child: _OffPill(
                      selected: off,
                      onTap: () async {
                        await applyWorkerProvider(kind: null, storage: storage);
                        if (!context.mounted) return;
                        setState(() {
                          _url.text = storage.workerRemoteApiUrl;
                          _model.text = storage.workerRemoteModelName;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RemoteProviderBar(
                selected: kind,
                noneSelected: off,
                showOmlx: Platform.isMacOS,
                koboldEnabled: !backendManager.isIntelMac,
                onSelected: (next) async {
                  await applyWorkerProvider(
                    kind: next,
                    storage: storage,
                    urlController: _url,
                    modelController: _model,
                  );
                  if (!context.mounted) return;
                  setState(() {});
                },
              ),
              if (showUrl) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _url,
                  decoration: const InputDecoration(
                    labelText: 'Worker API URL',
                    hintText: 'https://your-server.example/v1',
                  ),
                  onSubmitted: (v) => storage.setWorkerRemoteApiUrl(v.trim()),
                  onTapOutside: (_) =>
                      storage.setWorkerRemoteApiUrl(_url.text.trim()),
                ),
              ],
              if (showModel) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _model,
                  decoration: const InputDecoration(
                    labelText: 'Worker model',
                    hintText: 'Same host can use a different model id',
                  ),
                  onSubmitted: (v) =>
                      storage.setWorkerRemoteModelName(v.trim()),
                  onTapOutside: (_) =>
                      storage.setWorkerRemoteModelName(_model.text.trim()),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _fetching
                        ? null
                        : () => _browseModels(context, llm, storage),
                    icon: _fetching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.search,
                            size: 16,
                            color: AppColors.porchAmberOf(context),
                          ),
                    label: Text(
                      'Browse models',
                      style: TextStyle(color: AppColors.porchAmberOf(context)),
                    ),
                  ),
                ),
              ],
              if (needsKey) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _key,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Worker API key',
                    hintText:
                        storage
                            .remoteApiKeyFor(
                              resolvedLaneApiUrl(
                                storage.workerBackendType,
                                storage.workerRemoteApiUrl,
                              ),
                            )
                            .isNotEmpty
                        ? '•••••• (leave blank to keep)'
                        : 'Key for this worker host',
                  ),
                  onSubmitted: (v) {
                    if (v.trim().isEmpty) return;
                    storage.setRemoteApiKeyFor(
                      resolvedLaneApiUrl(
                        storage.workerBackendType,
                        storage.workerRemoteApiUrl,
                      ),
                      v.trim(),
                    );
                    _key.clear();
                  },
                ),
              ],
              if (!off && storage.workerBackendType == 'kobold')
                Text(
                  'Side jobs will start KoboldCPP using the model and GPU '
                  'settings from the Models tab. Chat speech stays on your '
                  'API host.',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _browseModels(
    BuildContext context,
    LLMProvider llm,
    StorageService storage,
  ) async {
    setState(() => _fetching = true);
    try {
      if (_url.text.trim().isNotEmpty) {
        await storage.setWorkerRemoteApiUrl(_url.text.trim());
      }
      final list = await llm.workerRemoteService.fetchAvailableModels();
      if (!context.mounted) return;
      setState(() => _models = list);
      showGenericModelSearchDialog<RemoteModelInfo>(
        context,
        _models,
        title: 'Worker model',
        getTitle: (m) => m.name,
        getSubtitle: (m) => m.id,
        onSelected: (m) {
          storage.setWorkerRemoteModelName(m.id);
          _model.text = m.id;
        },
      );
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }
}

class _OffPill extends StatelessWidget {
  const _OffPill({required this.selected, required this.onTap});

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
            'Off — same as chat',
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
