// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/dialogs/kcpps_editor/kcpps_editor.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/utils.dart';

import 'kobold_card_note.dart';
import 'kobold_context_control.dart';
import 'kobold_speed_test_button.dart';

/// "Local model": how the model runs here, in plain words, and the one
/// thing a user sets in auto mode, the context, with the speed test below
/// it. With a preset in use it says what the preset does instead.
class KoboldStatusCard extends StatefulWidget {
  const KoboldStatusCard({
    super.key,
    this.reloadChat,
    this.unified,
    this.speedTest,
  });

  /// Puts a changed context into the running KoboldCpp. The app's own
  /// when null.
  final Future<void> Function()? reloadChat;

  /// For tests: Apple Silicon's one memory pool or not.
  final bool? unified;

  /// For tests: the speed test. The app's own when null.
  final KoboldSpeedTest? speedTest;

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

  /// The speed test this card follows, and what it measured for the model
  /// here, which a launch runs (read again when the test ends).
  KoboldSpeedTest? _test;
  KoboldKnobs? _measured;
  String _measuredKey = '';

  /// Leaving the page does not cancel a reload: the new context is saved,
  /// and KoboldCpp would keep running with the old one.
  @override
  void dispose() {
    _runReload();
    _test?.removeListener(_onTest);
    super.dispose();
  }

  void _follow(KoboldSpeedTest? test) {
    if (identical(test, _test)) return;
    _test?.removeListener(_onTest);
    _test = test;
    test?.addListener(_onTest);
  }

  void _onTest() {
    if (mounted) setState(() {});
  }

  Future<void> _readMeasured(
    String key,
    StorageService storage,
    String model,
    HardwareInfo? hardware,
  ) async {
    final knobs = await koboldMeasuredForCard(
      storage,
      model: model,
      hardware: hardware,
      unified: widget.unified,
    );
    if (mounted && key == _measuredKey) setState(() => _measured = knobs);
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
    _reload = Timer(kKoboldContextReloadDelay, _runReload);
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
    final hw = hardware.hardwareInfo;
    final test =
        widget.speedTest ?? context.read<LLMProvider?>()?.koboldSpeedTest;
    _follow(test);
    final measuredKey = [
      model,
      hw?.gpuName,
      b.useCublas,
      b.useVulkan,
      b.useRocm,
      b.useMetal,
      b.gpuId,
      storage.presetSettings.modelPresetMap[model],
      test?.phase,
      test?.line,
    ].join('|');
    if (measuredKey != _measuredKey) {
      _measuredKey = measuredKey;
      _readMeasured(measuredKey, storage, model, hw);
    }
    // Everything KoboldStatusFacts.of reads: a change to any of it works the
    // facts out again, and a rebuild alone does not.
    final key = [
      model,
      b.contextSize,
      b.kvQuant,
      b.flashAttentionEnabled,
      b.batchAutomatic,
      b.blasBatchSize,
      b.gpuLayersManual,
      b.gpuLayers,
      b.mlockEnabled,
      b.gpuId,
      b.useCublas,
      b.useVulkan,
      b.useRocm,
      b.useMetal,
      b.rocmFlashAttentionFailed,
      b.keepRecentChats,
      _bytes,
      free,
      hw?.vramMb,
      hw?.ramMb,
      hw?.vendor,
      hw?.hasCuda,
      hw?.hasMetal,
      _measured,
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
        measured: _measured,
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
          // Why it stopped on its own, from the status line, until the next
          // Start or Stop.
          if (kobold.phase == KoboldPhase.stopped &&
              kobold.modelLoadingStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              kobold.modelLoadingStatus,
              key: const ValueKey('local-model-stopped-why'),
              style: keText(
                context,
                size: 14,
                height: 1.45,
                color: AppColors.porchHoneyOf(context),
                weight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 16),
          ...preset != null
              ? _presetBody(context)
              : _autoBody(context, b, kobold, test),
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
      KcppsOk(:final config, :final raw) => kcppsPlainWords(
        config,
        machineCards: context.read<HardwareService>().hardwareInfo?.cardCount,
        swaLeftToKobold:
            kcppsSwaLeftToKobold(raw) && (_info?.hasSlidingWindow ?? false),
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
    KoboldSpeedTest? test,
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
      // The model was made for less chat than the app needs.
      if (facts.warning case final warning?) ...[
        KoboldCardNote(
          key: const ValueKey('local-model-short-model'),
          tint: AppColors.porchHoneyOf(context),
          warn: true,
          child: Text(warning, style: keText(context, size: 14, height: 1.45)),
        ),
        const SizedBox(height: 10),
      ],
      const SizedBox(height: 6),
      KoboldContextControl(
        facts: facts,
        contextSize: b.contextSize,
        pending: _pending,
        onPick: (c) {
          if (facts.verdicts[c]?.outcome == KoboldContextOutcome.tooBig) {
            setState(() => _pending = c);
          } else {
            _apply(c, kobold);
          }
        },
        onApply: (c) => _apply(c, kobold),
      ),
      if (test != null) ...[
        const SizedBox(height: 16),
        KoboldSpeedTestButton(
          test: test,
          model: _model ?? '',
          phase: kobold.phase,
        ),
      ],
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
}
