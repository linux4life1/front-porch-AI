// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The preset editor's "How this loads" panel as data: the parts of the
// card, what each is, and a verdict with its one-tap fix. Pure, so every
// sentence can be pinned by a test.

import 'package:front_porch_ai/utils/kobold_placement.dart';

import 'kobold_app_config.dart';
import 'kobold_fit.dart';

enum KoboldFitKind { fits, reduced, over }

enum KoboldBarPart { model, experts, cache, working, engine, unused, over }

/// One part of the bar: its size and its line in the legend.
class KoboldBarSegment {
  const KoboldBarSegment(this.part, this.mb, this.label, this.legend);

  final KoboldBarPart part;
  final int mb;

  /// Inside the bar ("Model 2.0").
  final String label;

  /// Beside it ("Model, always on the card · 2.0 GB").
  final String legend;
}

/// Where the model goes, by hand. Null fields mean KoboldCpp places it.
class KoboldPlacement {
  const KoboldPlacement.automatic() : gpuLayers = null, moeCpuLayers = 0;
  const KoboldPlacement.manual(this.gpuLayers, this.moeCpuLayers);

  final int? gpuLayers;
  final int moeCpuLayers;

  bool get manual => gpuLayers != null;
}

class KoboldFitView {
  const KoboldFitView({
    required this.load,
    required this.segments,
    required this.kind,
    required this.title,
    required this.text,
    this.fix,
    this.batchHint,
  });

  final KoboldLoad load;
  final List<KoboldBarSegment> segments;
  final KoboldFitKind kind;
  final String title;
  final String text;

  /// Manual placement over the free memory: the most that fits.
  final KoboldPlacement? fix;

  /// A smaller batch that puts more on the card: what it frees and what
  /// then fits ("one more layer's experts fit").
  final ({int batch, int freedMb, String what})? batchHint;

  /// "A batch of 512 frees 0.5 GB: one more layer's experts fit."
  String? get batchHintText {
    final h = batchHint;
    if (h == null || kind == KoboldFitKind.fits) return null;
    return h.what.endsWith('room')
        ? 'A batch of ${h.batch} would give ${h.what}.'
        : 'A batch of ${h.batch} frees ${_gb(h.freedMb)} GB: ${h.what}.';
  }
}

/// "2.0" GB from MB.
String _gb(int mb) => (mb / 1024).toStringAsFixed(1);

String _layersOf(int n, int of) => n == of ? 'all $of layers' : '$n of $of';

/// The panel for [fit] on [machine] with [placement]. Automatic placement
/// predicts KoboldCpp's fit, which keeps [paddingMb] spare; a placement by
/// hand is taken as given and checked against what is free.
KoboldFitView koboldFitView(
  KoboldFit fit,
  KoboldMachine machine,
  KoboldPlacement placement, {
  required int paddingMb,
}) {
  final free = machine.graphicsMb;
  final budget = machine.unified ? free : free - paddingMb;
  final load = placement.manual
      ? fit.load(
          gpuLayers: placement.gpuLayers,
          moeCpuBlocks: placement.moeCpuLayers,
        )
      : machine.unified
      ? fit.load()
      : fit.mostThatFits(budget);
  final card = load.cardMb + fit.extraCardMb;
  final overMb = card - free;
  final segments = _segments(fit, load, placement, overMb, paddingMb);

  KoboldPlacement? fix;
  final String title;
  final String text;
  final KoboldFitKind kind;
  if (overMb > 0 && (placement.manual || machine.unified)) {
    kind = KoboldFitKind.over;
    title = "This won't fit: ${_gb(overMb)} GB over.";
    if (machine.unified) {
      text =
          'With these settings it needs ${_gb(card)} GB, more than the '
          '${_gb(free)} GB the graphics may use here. A smaller context or '
          'chat memory size would fit.';
    } else {
      final most = fit.mostThatFits(free);
      final fits = most.cardMb + fit.extraCardMb <= free;
      fix = fits
          ? KoboldPlacement.manual(most.gpuLayers, most.moeCpuBlocks)
          : null;
      text =
          'With these numbers KoboldCpp runs out of graphics memory while '
          'loading or on the first reply. ${fits ? _mostSentence(most) : 'Not even one layer fits: lower the context or the chat memory size.'}';
    }
  } else if (load.allOnCard) {
    kind = KoboldFitKind.fits;
    title = 'It all fits on the card.';
    text = 'Replies come at full speed.';
  } else {
    kind = KoboldFitKind.reduced;
    title = placement.manual
        ? 'It fits, at reduced speed.'
        : 'It loads, at reduced speed.';
    text =
        '${placement.manual ? 'With these numbers' : 'KoboldCpp fits it like this:'} '
        '${_offCardSentence(load)}';
  }

  return KoboldFitView(
    load: load,
    segments: segments,
    kind: kind,
    title: title,
    text: text,
    fix: fix,
    batchHint: machine.unified
        ? null
        : placement.manual
        ? _freedHint(fit, load)
        : _batchHint(fit, load, budget),
  );
}

String _mostSentence(KoboldLoad most) {
  if (most.expertBlocks > 0 && most.gpuLayers == most.layerCount) {
    final off = most.expertBlocks - most.expertBlocksOnCard;
    return 'With everything else as it is, at most '
        '${most.expertBlocksOnCard} layers\' experts fit on the card (keep '
        'the first $off in system memory).';
  }
  return 'With everything else as it is, at most '
      '${_layersOf(most.gpuLayers, most.layerCount)} layers fit on the card.';
}

String _offCardSentence(KoboldLoad l) {
  if (l.gpuLayers < l.layerCount) {
    final off = l.layerCount - l.gpuLayers;
    return '${l.gpuLayers} of ${l.layerCount} layers on the card; the other '
        '$off run from system memory, which is much slower.';
  }
  final off = l.expertBlocks - l.expertBlocksOnCard;
  return off == l.expertBlocks
      ? "every layer's experts are read from system memory, which is slower."
      : "the other $off layers' experts are read from system memory, which "
            'is slower.';
}

/// With the model placed by hand: what a batch of 512 frees.
({int batch, int freedMb, String what})? _freedHint(
  KoboldFit fit,
  KoboldLoad load,
) {
  if (fit.batchSize <= 512) return null;
  final freed =
      load.computeMb -
      fit
          .copyWith(batchSize: 512)
          .load(gpuLayers: load.gpuLayers, moeCpuBlocks: load.moeCpuBlocks)
          .computeMb;
  if (freed <= 0) return null;
  return (batch: 512, freedMb: freed, what: '${_gb(freed)} GB more room');
}

/// A batch of 512 when it puts more on the card than [load] does.
({int batch, int freedMb, String what})? _batchHint(
  KoboldFit fit,
  KoboldLoad load,
  int budget,
) {
  if (fit.batchSize <= 512 || load.allOnCard) return null;
  final small = fit.copyWith(batchSize: 512).mostThatFits(budget);
  final freed = load.computeMb - small.computeMb;
  final more = small.gpuLayers > load.gpuLayers
      ? small.gpuLayers - load.gpuLayers
      : small.expertBlocksOnCard - load.expertBlocksOnCard;
  if (more <= 0 || freed <= 0) return null;
  final what = small.gpuLayers > load.gpuLayers
      ? (more == 1 ? 'one more layer fits' : '$more more layers fit')
      : (more == 1
            ? "one more layer's experts fit"
            : "$more more layers' experts fit");
  return (batch: 512, freedMb: freed, what: what);
}

List<KoboldBarSegment> _segments(
  KoboldFit fit,
  KoboldLoad l,
  KoboldPlacement placement,
  int overMb,
  int paddingMb,
) {
  final moe = l.expertBlocks > 0;
  final allLayers = l.gpuLayers == l.layerCount;
  final model = moe && allLayers
      ? 'Model, always on the card'
      : allLayers
      ? 'Model'
      : 'Model layers on the card (${l.gpuLayers} of ${l.layerCount})';
  final experts = placement.manual
      ? 'Experts you put on the card'
      : 'Experts that also fit';
  final unused = -overMb;
  return [
    KoboldBarSegment(
      KoboldBarPart.model,
      l.modelMb + fit.extraCardMb,
      'Model ${_gb(l.modelMb + fit.extraCardMb)}',
      '$model · ${_gb(l.modelMb + fit.extraCardMb)} GB',
    ),
    if (moe)
      KoboldBarSegment(
        KoboldBarPart.experts,
        l.expertsMb,
        'Experts ${_gb(l.expertsMb)}',
        '$experts · ${_gb(l.expertsMb)} GB '
            '(${l.expertBlocksOnCard} of ${l.expertBlocks} layers)',
      ),
    KoboldBarSegment(
      KoboldBarPart.cache,
      l.cacheMb,
      _gb(l.cacheMb),
      'Chat memory, ${fit.contextSize ~/ 1024}k tokens · ${_gb(l.cacheMb)} GB',
    ),
    KoboldBarSegment(
      KoboldBarPart.working,
      l.computeMb,
      'Working ${_gb(l.computeMb)}',
      'Working space for a batch · ${_gb(l.computeMb)} GB',
    ),
    KoboldBarSegment(
      KoboldBarPart.engine,
      l.overheadMb,
      _gb(l.overheadMb),
      'KoboldCpp itself · ${_gb(l.overheadMb)} GB',
    ),
    if (overMb > 0)
      KoboldBarSegment(
        KoboldBarPart.over,
        overMb,
        'Over by ${_gb(overMb)}',
        'Over the free memory · ${_gb(overMb)} GB',
      )
    else
      KoboldBarSegment(
        KoboldBarPart.unused,
        unused,
        '',
        'Unused · ${_gb(unused)} GB${_unusedWhy(l, placement, paddingMb)}',
      ),
  ];
}

String _unusedWhy(KoboldLoad l, KoboldPlacement placement, int paddingMb) {
  if (l.allOnCard || placement.manual) return '';
  return koboldPaddingIsGreedy(paddingMb)
      ? ' (too little for another layer)'
      : ' (KoboldCpp keeps ${_gb(paddingMb)} GB spare)';
}
