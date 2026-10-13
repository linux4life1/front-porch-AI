// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_widgets.dart';

/// The stove for a Remote API: host tiles, the key box when the host has no
/// key, the chosen model, the sizes that host takes, and Generate. Nothing a
/// Remote API ignores (graphs, LoRAs, samplers) is on it.
class StudioRemoteStove extends StatefulWidget {
  const StudioRemoteStove({
    super.key,
    required this.panel,
    required this.backend,
    required this.onBackend,
    required this.onHost,
    required this.onSaveKey,
    required this.onModels,
    required this.onSize,
    required this.onAspect,
    required this.onResolution,
    required this.readyLine,
    required this.generateEnabled,
    this.promptKnobs,
    this.onRetry,
    this.onGenerate,
    this.showGenerate = true,
    this.errorText = '',
    this.generating = false,
    this.showModes = false,
    this.editing = false,
    this.onMode,
  });

  final RemoteStudioPanel panel;
  final String backend;
  final ValueChanged<String> onBackend;
  final ValueChanged<String> onHost;
  final ValueChanged<String> onSaveKey;
  final VoidCallback onModels;
  final ValueChanged<String> onSize;
  final ValueChanged<String> onAspect;
  final ValueChanged<String> onResolution;
  final String readyLine;
  final bool generateEnabled;

  /// Prompt review, style and prompt format: they shape the prompt the
  /// writer makes, so they stay reachable on Remote, folded away.
  final Widget? promptKnobs;
  final VoidCallback? onRetry;
  final VoidCallback? onGenerate;
  final bool showGenerate;
  final String errorText;
  final bool generating;
  final bool showModes;
  final bool editing;
  final ValueChanged<bool>? onMode;

  @override
  State<StudioRemoteStove> createState() => _StudioRemoteStoveState();
}

class _StudioRemoteStoveState extends State<StudioRemoteStove> {
  bool _promptOpen = false;

  @override
  Widget build(BuildContext context) {
    final panel = widget.panel;
    final primary = AppColors.textPrimary(context);
    final secondary = AppColors.textSecondary(context);
    final border = AppColors.borderOf(context);
    final accent = AppColors.porchAmberOf(context);
    TextStyle label() => TextStyle(color: secondary, fontSize: 14);
    Widget section(List<Widget> children) => Container(
      padding: const EdgeInsets.only(top: 18),
      margin: const EdgeInsets.only(top: 22),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
    final readyLine = panel.needsKey ? panel.needsKeyLine : widget.readyLine;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showModes)
              StudioStoveModes(editing: widget.editing, onMode: widget.onMode),
            Row(
              children: [
                Expanded(child: Text('Connection', style: label())),
                StudioBackendMenu(
                  backend: widget.backend,
                  onBackend: widget.onBackend,
                ),
              ],
            ),
            Text(
              'Remote API',
              style: TextStyle(
                color: primary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            RemoteImageHostChips(tiles: panel.tiles, onSelect: widget.onHost),
            const SizedBox(height: 10),
            Text(panel.url, style: TextStyle(color: secondary, fontSize: 13)),
            Text(
              panel.billing,
              style: TextStyle(
                color: secondary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 10),
            if (panel.needsKey)
              StudioRemoteKeyField(
                key: ValueKey('key-${panel.host.id}'),
                label: panel.keyPrompt,
                hint: panel.keyHint,
                note: panel.keyNote,
                onSave: widget.onSaveKey,
              )
            else
              Row(
                children: [
                  Text(
                    panel.status,
                    style: TextStyle(color: secondary, fontSize: 13),
                  ),
                  const SizedBox(width: 12),
                  if (widget.onRetry != null)
                    TextButton(
                      onPressed: widget.onRetry,
                      style: TextButton.styleFrom(foregroundColor: accent),
                      child: const Text(
                        'Check',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            if (!panel.needsKey) ...[
              section([
                Text('Model', style: label()),
                const SizedBox(height: 8),
                Text(
                  panel.modelName,
                  style: TextStyle(
                    color: primary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (panel.modelId.isNotEmpty &&
                    panel.modelId != panel.modelName) ...[
                  const SizedBox(height: 8),
                  Text(
                    panel.modelId,
                    style: TextStyle(
                      color: secondary,
                      fontSize: 13,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
                if (panel.badges.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [for (final badge in panel.badges) _Badge(badge)],
                  ),
                ],
                if (panel.price.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    panel.price,
                    style: TextStyle(color: primary, fontSize: 13),
                  ),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: const Key('image-remote-change-model'),
                    onPressed: widget.onModels,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      foregroundColor: accent,
                    ),
                    child: const Text(
                      'Change model',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ]),
              section(_size(label, secondary, primary)),
            ],
            if (widget.promptKnobs != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () => setState(() => _promptOpen = !_promptOpen),
                  style: TextButton.styleFrom(foregroundColor: accent),
                  child: Text(
                    _promptOpen ? 'Prompt options ▾' : 'Prompt options ▸',
                  ),
                ),
              ),
              if (_promptOpen) widget.promptKnobs!,
            ],
            section([
              Row(
                children: [
                  Expanded(
                    child: Text(
                      readyLine,
                      style: TextStyle(color: primary, fontSize: 14),
                    ),
                  ),
                  if (widget.showGenerate)
                    FilledButton(
                      onPressed: widget.generateEnabled && !panel.needsKey
                          ? widget.onGenerate
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: AppColors.onChaosAccent,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 12,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Generate'),
                    ),
                ],
              ),
            ]),
            if (widget.generating) const StudioGenProgress(),
            if (widget.errorText.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  widget.errorText,
                  style: TextStyle(color: AppColors.logError, fontSize: 13),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _size(
    TextStyle Function() label,
    Color secondary,
    Color primary,
  ) {
    final panel = widget.panel;
    if (panel.sizeMode == RemoteSizeMode.none) {
      return [
        Text('Size', style: label()),
        const SizedBox(height: 6),
        Text(panel.sizeNote, style: TextStyle(color: primary, fontSize: 14)),
      ];
    }
    Widget pills(List<RemoteChoice> choices, ValueChanged<String> onPick) =>
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in choices)
              StudioSizePill(
                label: c.label,
                selected: c.selected,
                onPressed: () => onPick(c.value),
              ),
          ],
        );
    final xai = panel.sizeMode == RemoteSizeMode.xai;
    return [
      Text(panel.sizeTitle, style: label()),
      const SizedBox(height: 10),
      pills(panel.sizes, xai ? widget.onAspect : widget.onSize),
      if (xai) ...[
        const SizedBox(height: 14),
        Text('Resolution', style: label()),
        const SizedBox(height: 10),
        pills(panel.resolutions, widget.onResolution),
      ],
      const SizedBox(height: 10),
      Text(panel.sizeNote, style: TextStyle(color: secondary, fontSize: 13)),
    ];
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Text(
          text,
          style: TextStyle(color: AppColors.textPrimary(context), fontSize: 12),
        ),
      ),
    );
  }
}
