// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'studio_desk_copy.dart';
import 'studio_gen_progress.dart';
import 'studio_size_fields.dart';
import 'studio_size_pill.dart';
import 'studio_stove_knobs.dart';

/// One LoRA sitting on the stove, with the badge the family check earned.
class StudioStoveLora {
  final String file;
  final String badge;

  const StudioStoveLora(this.file, this.badge);
}

/// The right-hand stove: connection, model, support files, LoRAs, size,
/// and the collapsed sampler block. Generate sits on this card.
class StudioStove extends StatefulWidget {
  const StudioStove({
    super.key,
    required this.backendName,
    required this.backend,
    required this.url,
    required this.onBackend,
    required this.onEditUrl,
    this.remoteNote,
    this.reachable = false,
    this.checkedDown = false,
    this.diffusionCount = 0,
    this.loraCount = 0,
    required this.familyLabel,
    required this.primaryFile,
    required this.why,
    required this.onGraphs,
    required this.onModels,
    required this.onGetModel,
    this.checkpointOnly = false,
    this.support = const [],
    this.onChangeSupport,
    this.loras = const [],
    this.loraBlocked = false,
    this.onAddLora,
    this.onGetLora,
    this.onAnyway,
    required this.width,
    required this.height,
    required this.onSize,
    required this.steps,
    required this.cfg,
    required this.sampler,
    required this.scheduler,
    required this.onSteps,
    required this.onCfg,
    required this.onSampler,
    required this.onScheduler,
    this.drawThings = false,
    this.drawThingsSampler = 16,
    this.onDrawThingsSampler,
    required this.readyLine,
    required this.generateEnabled,
    this.onGenerate,
    this.showGenerate = true,
    this.errorText = '',
    this.generating = false,
    this.onRetry,
    this.showModes = false,
    this.editing = false,
    this.onMode,
    this.status = '',
  });

  final String backendName;
  final String backend;
  final String url;
  final ValueChanged<String> onBackend;
  final VoidCallback onEditUrl;
  final Widget? remoteNote;
  final bool reachable;
  final bool checkedDown;
  final int diffusionCount;
  final int loraCount;
  final String familyLabel;
  final String primaryFile;
  final String why;
  final VoidCallback onGraphs;
  final VoidCallback onModels;
  final VoidCallback onGetModel;
  final bool checkpointOnly;
  final List<StudioSupportRow> support;
  final ValueChanged<String>? onChangeSupport;
  final List<StudioStoveLora> loras;
  final bool loraBlocked;
  final VoidCallback? onAddLora;
  final VoidCallback? onGetLora;
  final VoidCallback? onAnyway;
  final int width;
  final int height;
  final void Function(int width, int height) onSize;
  final int steps;
  final double cfg;
  final String sampler;
  final String scheduler;
  final ValueChanged<String> onSteps;
  final ValueChanged<String> onCfg;
  final ValueChanged<String> onSampler;
  final ValueChanged<String> onScheduler;
  final bool drawThings;
  final int drawThingsSampler;
  final ValueChanged<int>? onDrawThingsSampler;
  final String readyLine;
  final bool generateEnabled;
  final VoidCallback? onGenerate;
  final bool showGenerate;
  final String errorText;
  final bool generating;
  final VoidCallback? onRetry;
  final bool showModes;
  final bool editing;
  final ValueChanged<bool>? onMode;
  final String status;

  @override
  State<StudioStove> createState() => _StudioStoveState();
}

class _StudioStoveState extends State<StudioStove> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final primary = AppColors.textPrimary(context);
    final secondary = AppColors.textSecondary(context);
    final drawLabel = studioDrawThingsLabel(widget.drawThingsSampler);
    final summary = studioAdvancedSummary(
      steps: widget.steps,
      cfg: widget.cfg,
      sampler: widget.drawThings ? drawLabel : widget.sampler,
      scheduler: widget.drawThings ? drawLabel : widget.scheduler,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderOf(context)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showModes) _modes(context),
            _connection(context, primary, secondary),
            const SizedBox(height: 12),
            Text(
              'Model',
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.familyLabel,
              style: TextStyle(color: primary, fontWeight: FontWeight.w700),
            ),
            if (widget.primaryFile.isNotEmpty)
              Text(widget.primaryFile, style: TextStyle(color: primary)),
            Text(widget.why, style: TextStyle(color: secondary, fontSize: 12)),
            Wrap(
              spacing: 4,
              children: [
                if (widget.backend == 'comfyui')
                  TextButton(
                    onPressed: widget.onGraphs,
                    child: const Text('Change graph'),
                  ),
                TextButton(
                  onPressed: widget.onModels,
                  child: const Text('Change model'),
                ),
                TextButton(
                  onPressed: widget.onGetModel,
                  child: const Text('Get a model from CivitAI'),
                ),
              ],
            ),
            if (widget.status.isNotEmpty)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(widget.status, style: TextStyle(color: primary)),
                ],
              ),
            if (widget.checkpointOnly)
              Text(
                kStudioCheckpointSupport,
                style: TextStyle(color: secondary, fontSize: 12, height: 1.35),
              ),
            if (widget.support.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'This graph also loads',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final row in widget.support)
                _supportRow(context, row, primary, secondary),
              Text(
                kStudioLoraFamilyNote,
                style: TextStyle(color: secondary, fontSize: 12, height: 1.35),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'LoRA',
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            for (final row in widget.loras)
              Row(
                children: [
                  Expanded(
                    child: Text(row.file, style: TextStyle(color: primary)),
                  ),
                  Text(row.badge, style: TextStyle(color: secondary)),
                ],
              ),
            if (widget.loraBlocked) ...[
              Text(
                'Generate stays off until you pick a matching LoRA or press Use anyway.',
                style: TextStyle(color: secondary, fontSize: 12, height: 1.35),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: widget.onAnyway,
                  child: const Text('Use anyway'),
                ),
              ),
            ],
            Wrap(
              spacing: 4,
              children: [
                TextButton(
                  onPressed: widget.onAddLora,
                  child: const Text('Add'),
                ),
                TextButton(
                  onPressed: widget.onGetLora,
                  child: const Text('Get a LoRA from CivitAI'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Size',
              style: TextStyle(
                color: secondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final chip in kStudioSizeChips)
                  StudioSizePill(
                    label: chip.$3,
                    selected:
                        chip.$1 == widget.width && chip.$2 == widget.height,
                    onPressed: () => widget.onSize(chip.$1, chip.$2),
                  ),
              ],
            ),
            StudioSizeFields(
              key: ValueKey('${widget.width}x${widget.height}'),
              width: widget.width,
              height: widget.height,
              onChanged: widget.onSize,
            ),
            Text(
              studioSizeNote(widget.width, widget.height),
              style: TextStyle(color: secondary, fontSize: 12, height: 1.35),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _open = !_open),
                child: Text(
                  _open ? 'Advanced ▾ $summary' : 'Advanced ▸ $summary',
                ),
              ),
            ),
            if (_open) ...[
              StudioStoveKnobs(
                drawThings: widget.drawThings,
                drawThingsSampler: widget.drawThingsSampler,
                onDrawThingsSampler: widget.onDrawThingsSampler,
                steps: widget.steps,
                cfg: widget.cfg,
                sampler: widget.sampler,
                scheduler: widget.scheduler,
                onSteps: widget.onSteps,
                onCfg: widget.onCfg,
                onSampler: widget.onSampler,
                onScheduler: widget.onScheduler,
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.readyLine,
                    style: TextStyle(color: secondary, fontSize: 12),
                  ),
                ),
                if (widget.showGenerate)
                  FilledButton(
                    onPressed: widget.generateEnabled
                        ? widget.onGenerate
                        : null,
                    child: const Text('Generate'),
                  ),
              ],
            ),
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

  Widget _modes(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: widget.editing ? () => widget.onMode?.call(false) : null,
            child: const Text('Create'),
          ),
          TextButton(
            onPressed: widget.editing ? null : () => widget.onMode?.call(true),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Widget _connection(BuildContext context, Color primary, Color secondary) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Connection',
                style: TextStyle(
                  color: secondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(widget.backendName, style: TextStyle(color: primary)),
              InkWell(
                onTap: widget.onEditUrl,
                child: Text(
                  widget.url,
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
              if (widget.remoteNote != null) widget.remoteNote!,
              if (widget.reachable)
                Text(
                  'Reachable · ${widget.diffusionCount} diffusion files · ${widget.loraCount} LoRAs',
                  style: TextStyle(color: secondary, fontSize: 12),
                )
              else if (widget.backend == 'comfyui' || (widget.checkedDown))
                Text(
                  'Not running',
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              if (widget.onRetry != null)
                TextButton(
                  onPressed: widget.onRetry,
                  child: const Text('Check'),
                ),
            ],
          ),
        ),
        PopupMenuButton<String>(
          onSelected: widget.onBackend,
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'remote', child: Text('Remote')),
            PopupMenuItem(value: 'comfyui', child: Text('ComfyUI')),
            PopupMenuItem(value: 'a1111', child: Text('Automatic1111')),
            PopupMenuItem(value: 'drawthings', child: Text('Draw Things')),
          ],
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text('Change…'),
          ),
        ),
      ],
    );
  }

  Widget _supportRow(
    BuildContext context,
    StudioSupportRow row,
    Color primary,
    Color secondary,
  ) {
    final name = row.file.isEmpty ? 'Not chosen' : row.file;
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            row.role,
            style: TextStyle(color: secondary, fontSize: 12),
          ),
        ),
        Expanded(
          child: Text(name, style: TextStyle(color: primary)),
        ),
        TextButton(
          onPressed: () => widget.onChangeSupport?.call(row.token),
          child: const Text('Change'),
        ),
      ],
    );
  }
}
