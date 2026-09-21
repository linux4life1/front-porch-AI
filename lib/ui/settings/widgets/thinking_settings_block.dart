// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Request-thinking switch + this model's real strength chips. Off is locked
// when the model cannot disable reasoning. A Nano poke at pick time fills
// the menu when the provider does not advertise it.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/capability/capability.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/settings/widgets/thinking_strength_control.dart';

/// Thinking switch + strength chips for Settings and per-chat settings.
class ThinkingSettingsBlock extends StatefulWidget {
  const ThinkingSettingsBlock({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.effort,
    required this.onEffortChanged,
    this.modelId = '',
    this.compact = false,
  });

  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final String effort;
  final ValueChanged<String> onEffortChanged;
  final String modelId;
  final bool compact;

  @override
  State<ThinkingSettingsBlock> createState() => _ThinkingSettingsBlockState();
}

class _ThinkingSettingsBlockState extends State<ThinkingSettingsBlock> {
  @override
  void initState() {
    super.initState();
    kReasoningEffortCatalogTick.addListener(_onCatalog);
    WidgetsBinding.instance.addPostFrameCallback((_) => _kickProbe());
  }

  @override
  void didUpdateWidget(ThinkingSettingsBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.modelId != widget.modelId) _kickProbe();
  }

  @override
  void dispose() {
    kReasoningEffortCatalogTick.removeListener(_onCatalog);
    super.dispose();
  }

  void _onCatalog() {
    if (mounted) setState(() {});
  }

  StorageService? get _storage {
    try {
      return Provider.of<StorageService>(context, listen: false);
    } catch (_) {
      return null;
    }
  }

  bool get _isLocal {
    try {
      return Provider.of<LLMProvider>(context, listen: false).isLocal;
    } catch (_) {
      return false;
    }
  }

  bool get _isOmlx {
    try {
      return Provider.of<LLMProvider>(context, listen: false).activeBackend ==
          BackendType.omlx;
    } catch (_) {
      return false;
    }
  }

  void _kickProbe() {
    if (!mounted) return;
    final storage = _storage;
    if (storage == null) return;
    // Local (managed KoboldCpp): the capability is in the loaded GGUF's chat
    // template, not in a provider's 400 — read the file instead of poking.
    // Off the build path by construction: this runs from initState's
    // post-frame hook / didUpdateWidget, and the widget reads only the cached
    // verdict via peek().
    if (_isLocal) {
      final path = _localModelPath;
      if (path.isEmpty) return;
      if (ReasoningSupportResolver.instance.isResolved(path)) return;
      unawaited(ReasoningSupportResolver.instance.resolveLocalGguf(path));
      return;
    }
    // oMLX: same detector, different source. Status + on-disk jinja — never
    // a completions poke, which would load a 30–90 GB model.
    if (_isOmlx) {
      final model = widget.modelId;
      if (model.isEmpty) return;
      if (ReasoningSupportResolver.instance.isResolved(model)) return;
      unawaited(
        ReasoningSupportResolver.instance.resolveOmlx(
          apiUrl: 'http://localhost:8000/v1',
          modelName: model,
          apiKey: storage.backendSettings.remoteApiKey,
        ),
      );
      return;
    }
    // LM Studio (or any local OpenAI URL): confirm /api/v0/models then read
    // the GGUF. Do NOT poke — JIT loading would pull the model in, and the
    // 400 listing is the server's enum, not this model's capability.
    if (isLocalRemoteUrl(storage.backendSettings.remoteApiUrl)) {
      final model = widget.modelId;
      if (model.isEmpty) return;
      if (ReasoningSupportResolver.instance.isResolved(model)) return;
      unawaited(
        ReasoningSupportResolver.instance.resolveLmStudio(
          apiUrl: storage.backendSettings.remoteApiUrl,
          modelName: model,
          apiKey: storage.backendSettings.remoteApiKey,
        ),
      );
      return;
    }
    if (widget.modelId.isEmpty) return;
    kickReasoningEffortProbe(
      model: widget.modelId,
      apiUrl: storage.backendSettings.remoteApiUrl,
      apiKey: storage.backendSettings.remoteApiKey,
    );
  }

  /// The .gguf whose thinking template we should read. In .kcpps preset
  /// mode that is the model the preset loads, not the picker leftover
  /// (lastUsedModelPath) — otherwise the switch describes the wrong file.
  String get _localModelPath {
    final preset = _storage?.backendSettings.activeKcppsPath;
    if (preset != null && preset.isNotEmpty) {
      return _storage?.backendSettings.kcppsModelPath ?? '';
    }
    return _storage?.backendSettings.lastUsedModelPath ?? '';
  }

  /// The thinking capability already resolved for this backend, or null
  /// while it is still being read / could not be read. Build-safe: peek only.
  ThinkingSupport? get _templateSupport {
    if (_isLocal) {
      final path = _localModelPath;
      return path.isEmpty ? null : ReasoningSupportResolver.instance.peek(path);
    }
    if (_isOmlx || _isLocalRemote) {
      final id = widget.modelId;
      return id.isEmpty ? null : ReasoningSupportResolver.instance.peek(id);
    }
    return null;
  }

  bool get _isLocalRemote {
    final url = _storage?.backendSettings.remoteApiUrl ?? '';
    return url.isNotEmpty && isLocalRemoteUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final local = _isLocal;
    // The identity the shared chip/caption machinery keys on. Local models
    // are keyed by their .gguf path, which is what the resolver registers
    // under — so one store, one set of helpers, no local-only fork. It stays
    // EMPTY until the file has actually been read: an unresolved (or
    // preset-mode) local model must fall back to the generic chips rather
    // than claim knowledge we do not have.
    final templateSupport = _templateSupport;
    final effectiveModelId = local
        ? (templateSupport == null ? '' : _localModelPath)
        : widget.modelId;
    final mandatory = reasoningEffortIsMandatory(effectiveModelId);
    final thinkingOn = local
        ? widget.enabled
        : reasoningEffortThinkingOn(widget.modelId, widget.enabled);
    final pending = (_isOmlx || _isLocalRemote)
        ? widget.modelId.isNotEmpty &&
              !ReasoningSupportResolver.instance.isResolved(widget.modelId)
        : !local &&
              reasoningEffortMenuPending(
                widget.modelId,
                apiUrl: _storage?.backendSettings.remoteApiUrl ?? '',
              );
    // A model whose template has no thinking machinery at all: the switch and
    // the chips would both be no-ops, so say that instead of implying they work.
    final localCannotThink = templateSupport == ThinkingSupport.none;
    // Template toggle (oMLX/GGUF) OR a remote poke that learned on/off only
    // (NanoGPT returning the host enum, not this model's levels).
    final toggleOnly =
        templateSupport == ThinkingSupport.toggle ||
        reasoningEffortIsToggleOnly(effectiveModelId);
    final strengthChips = reasoningEffortChipsFor(effectiveModelId);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Request thinking',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: widget.compact ? 14 : null,
                ),
              ),
            ),
            Switch(
              value: thinkingOn,
              onChanged: mandatory || localCannotThink
                  ? null
                  : widget.onEnabledChanged,
              activeTrackColor: AppColors.formMasterAccent,
            ),
          ],
        ),
        if (localCannotThink)
          Padding(
            padding: EdgeInsets.only(top: widget.compact ? 2 : 4),
            child: Text(
              'This model has no thinking mode — its chat template never '
              'produces think-steps, so this switch would do nothing.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        if (toggleOnly)
          Padding(
            padding: EdgeInsets.only(top: widget.compact ? 2 : 4),
            child: Text(
              'This model thinks on or off only — it has no strength levels, '
              'so there are no chips to pick.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        if (mandatory)
          Padding(
            padding: EdgeInsets.only(top: widget.compact ? 2 : 4),
            child: Text(
              'This model always thinks — Off is not available.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        if (pending)
          Padding(
            padding: EdgeInsets.only(top: widget.compact ? 2 : 4),
            child: Text(
              (_isOmlx || _isLocalRemote)
                  ? 'Reading this model\'s thinking mode…'
                  : 'Asking this provider which thinking levels it accepts…',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        if (thinkingOn && !localCannotThink && strengthChips.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: widget.compact ? 4 : 12),
            child: ThinkingStrengthControl(
              compact: widget.compact,
              value: widget.effort,
              modelId: effectiveModelId,
              onChanged: widget.onEffortChanged,
            ),
          )
        else if (!widget.compact)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Turn on for reasoning models so their think-steps are '
              'captured under each reply. The chips then show this '
              'model\'s real levels.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Enable to request thinking from compatible models. '
              'Strength maps to the levels the model accepts.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}
