// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_prompts.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor_style.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'package:front_porch_ai/services/kobold_status_facts.dart';

/// "Local model": how the model runs here, in plain words, and the one
/// thing a user sets in auto mode, the context. With a preset in use it
/// says what the preset does instead.
class KoboldStatusCard extends StatefulWidget {
  const KoboldStatusCard({super.key, this.reloadChat, this.unified});

  /// Puts a changed context into the running KoboldCpp. The app's own
  /// when null.
  final Future<void> Function()? reloadChat;

  /// For tests: Apple Silicon's one memory pool or not.
  final bool? unified;

  @override
  State<KoboldStatusCard> createState() => _KoboldStatusCardState();
}

class _KoboldStatusCardState extends State<KoboldStatusCard> {
  String? _model;
  GGUFModelInfo? _info;
  int? _bytes;

  /// The model file has been looked at: read, or not readable.
  bool _modelRead = false;
  String? _presetPath;
  KcppsRead? _preset;
  KoboldStatusFacts? _facts;
  String _factsKey = '';
  bool _readingFree = false;

  /// A context too big for this computer, waiting for "keep anyway".
  int? _pending;

  /// The reload a context change waits to run, and the timer that runs it.
  Future<void> Function()? _reloadNow;
  Timer? _reload;

  /// Leaving the page does not cancel a reload: the new context is saved,
  /// and KoboldCpp would keep running with the old one.
  @override
  void dispose() {
    _runReload();
    super.dispose();
  }

  /// Runs the waiting reload now, if one waits.
  void _runReload() {
    _reload?.cancel();
    _reload = null;
    final run = _reloadNow;
    _reloadNow = null;
    run?.call().catchError(
      (Object e) => debugPrint('[Local model] reload failed: $e'),
    );
  }

  Future<void> _readModel(String model) async {
    GGUFModelInfo? info;
    int? bytes;
    if (model.isNotEmpty) {
      try {
        info = await GGUFParser.getModelArchitectureInfo(model);
        bytes = await File(model).length();
      } on FileSystemException catch (e) {
        debugPrint('[Local model] cannot read $model: $e');
      }
    }
    if (!mounted || model != _model) return;
    setState(() {
      _info = info;
      _bytes = bytes;
      _modelRead = true;
    });
  }

  Future<void> _readPreset(String path) async {
    final preset = await KcppsLibrary.open(path);
    if (mounted && path == _presetPath) setState(() => _preset = preset.read);
  }

  Future<void> _readFree(HardwareService hardware) async {
    _readingFree = true;
    final free = await hardware.readFreeMemory(
      gpuId: context.read<StorageService>().backendSettings.gpuId,
    );
    hardware.freeBeforeEngine = free;
    if (mounted) setState(() {});
  }

  Future<void> _apply(int tokens, KoboldService kobold) async {
    // Everything the page provides is taken before the first wait: it may
    // be gone by the end of it.
    final settings = context.read<StorageService>().backendSettings;
    final reload =
        widget.reloadChat ?? context.read<LLMProvider>().reloadChatKobold;
    setState(() => _pending = null);
    await settings.setContextSize(tokens);
    if (!kobold.isRunning) return;
    // A few taps in a row reload once.
    _reload?.cancel();
    _reloadNow = reload;
    _reload = Timer(const Duration(milliseconds: 1500), _runReload);
  }

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final kobold = context.watch<KoboldService>();
    final hardware = context.watch<HardwareService>();
    final b = storage.backendSettings;
    final model = b.lastUsedModelPath ?? '';
    if (model != _model) {
      _model = model;
      _info = null;
      _bytes = null;
      _modelRead = false;
      _readModel(model);
    }
    final preset = b.activeKcppsPath;
    if (preset != _presetPath) {
      _presetPath = preset;
      _preset = null;
      if (preset != null) _readPreset(preset);
    }
    final free = hardware.freeBeforeEngine ?? kobold.freeBeforeLaunch;
    if (free == null && !kobold.isRunning && !_readingFree) {
      _readFree(hardware);
    }
    // Everything KoboldStatusFacts.of reads: a change to any of it works the
    // facts out again, and a rebuild alone does not.
    final hw = hardware.hardwareInfo;
    final key = [
      model,
      b.contextSize,
      b.kvQuant,
      b.flashAttentionEnabled,
      b.koboldContextMode,
      b.batchAutomatic,
      b.blasBatchSize,
      b.gpuId,
      b.useCublas,
      b.useVulkan,
      b.useRocm,
      b.useMetal,
      b.rocmFlashAttentionFailed,
      _bytes,
      free,
      hw?.vramMb,
      hw?.ramMb,
      hw?.vendor,
      hw?.hasCuda,
      hw?.hasMetal,
    ].join('|');
    if (key != _factsKey) {
      _factsKey = key;
      _facts = KoboldStatusFacts.of(
        storage: storage,
        hardware: hardware.hardwareInfo,
        free: free,
        info: _info,
        bytes: _bytes,
        unified: widget.unified,
      );
    }

    return Container(
      key: const ValueKey('local-model-card'),
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairlineOf(context, 0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, kobold, preset == null ? model : null),
          const SizedBox(height: 16),
          ...preset != null
              ? _presetBody(context)
              : _autoBody(context, b, kobold),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, KoboldService kobold, String? model) {
    final (label, color) = switch (kobold.phase) {
      KoboldPhase.unloaded => ('Unloaded', AppColors.slateFaintOf(context)),
      KoboldPhase.ready => ('Ready', AppColors.journalAccentOf(context)),
      KoboldPhase.starting ||
      KoboldPhase.loading => ('Loading…', AppColors.porchHoneyOf(context)),
      KoboldPhase.stopped => ('Stopped', AppColors.slateFaintOf(context)),
    };
    final name = model == null
        ? (_preset is KcppsOk
              ? koboldModelName((_preset as KcppsOk).config.modelPath)
              : null)
        : model.isEmpty
        ? null
        : koboldModelName(model);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Local model',
                  style: keText(context, size: 18, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${name ?? 'No model chosen'} · '
                '${kobold.isRunning ? 'running' : 'not running'}',
                style: keText(
                  context,
                  size: 14,
                  color: AppColors.slateMutedOf(context),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: keText(
              context,
              size: 12,
              weight: FontWeight.w700,
              color: AppColors.onJournalAccent,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _presetBody(BuildContext context) {
    final read = _preset;
    final name = kcppsPresetName(_presetPath!);
    final text = switch (read) {
      null => 'Reading the preset…',
      KcppsBroken(:final reason) =>
        'The preset "$name" cannot be read: $reason',
      KcppsOk(:final config) => kcppsPlainWords(
        config,
        machineCards: context.read<HardwareService>().hardwareInfo?.cardCount,
      ),
    };
    return [
      _line(context, 'Uses your preset "$name".'),
      const SizedBox(height: 10),
      Text(
        text,
        key: const ValueKey('local-model-preset-words'),
        style: keText(context, size: 14, height: 1.45),
      ),
    ];
  }

  List<Widget> _autoBody(
    BuildContext context,
    BackendSettings b,
    KoboldService kobold,
  ) {
    final facts = _facts;
    if (facts == null) {
      return [
        _line(
          context,
          (_model ?? '').isEmpty
              ? 'Choose a model above to see how it runs here.'
              : !_modelRead
              ? 'Reading the model file…'
              : _info == null || _bytes == null
              ? 'The model file could not be read. Is it still in its folder? '
                    'You can choose another model above.'
              : 'Still finding out what this computer can do…',
        ),
      ];
    }
    return [
      for (final line in facts.lines) ...[
        _line(context, line),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      _contextControl(context, facts, b, kobold),
    ];
  }

  Widget _line(BuildContext context, String text) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: KeMark(AppColors.porchAmberOf(context), round: true, size: 8),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(text, style: keText(context, size: 14, height: 1.45)),
      ),
    ],
  );

  Widget _contextControl(
    BuildContext context,
    KoboldStatusFacts facts,
    BackendSettings b,
    KoboldService kobold,
  ) {
    final picked = _pending ?? b.contextSize;
    final verdict = facts.verdicts[picked];
    final words = verdict == null
        ? null
        : koboldContextWords(
            verdict,
            largestGood: facts.largestGood,
            isCurrent: picked == b.contextSize,
          );
    final kind = verdict?.outcome;
    final tint = switch (kind) {
      KoboldContextOutcome.tooBig => AppColors.alertRedOf(context),
      KoboldContextOutcome.tooSmall => AppColors.porchHoneyOf(context),
      _ => AppColors.journalAccentOf(context),
    };
    final ok =
        kind != KoboldContextOutcome.tooBig &&
        kind != KoboldContextOutcome.tooSmall;
    final best = facts.largestGood;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.insetPanelOf(context),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Context: how much chat history the character remembers',
            style: keText(context, size: 14, weight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          KeChoices<int>(
            key: const ValueKey('local-model-context'),
            values: facts.choices,
            selected: picked,
            expand: false,
            label: koboldTokens,
            onSelected: (c) {
              if (facts.verdicts[c]?.outcome == KoboldContextOutcome.tooBig) {
                setState(() => _pending = c);
              } else {
                _apply(c, kobold);
              }
            },
          ),
          if (words != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('local-model-verdict'),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: tint.withValues(alpha: ok ? 0.12 : 0.14),
                borderRadius: BorderRadius.circular(10),
                border: ok
                    ? null
                    : Border.all(color: tint.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ok
                        ? KeMark(tint, round: true, size: 12)
                        : Icon(Icons.warning_rounded, color: tint, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${words.title} ',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          TextSpan(text: words.text),
                        ],
                      ),
                      style: keText(context, size: 14, height: 1.45),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_pending case final big?) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                if (best != null)
                  KeButton(
                    'Use ${koboldTokens(best)} tokens',
                    kind: KeButtonKind.amber,
                    onPressed: () => _apply(best, kobold),
                  ),
                KeButton(
                  'Keep ${koboldTokens(big)} anyway…',
                  onPressed: () async {
                    final keep = await askKcpps(
                      context,
                      title: 'Keep ${koboldTokens(big)} tokens?',
                      text: words?.text ?? '',
                      yes: 'Keep it',
                    );
                    if (keep && mounted) await _apply(big, kobold);
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
