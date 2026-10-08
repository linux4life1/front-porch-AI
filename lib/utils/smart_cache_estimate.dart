// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// KoboldCpp's smart cache: what its slots cost and how many to ask for.
//
// A slot keeps one conversation's cache in system memory. Going back to a
// saved conversation then takes a fraction of a second instead of reading
// the whole chat again (0.2 s against 2.8 s for 2,200 tokens on a 16 GB
// card; minutes on a slow machine). Slots only work with fast forward on.
// Each one takes system memory, so on a machine where the model already
// needs more than is free, slots take memory from the model and slow it.

import 'gguf_model_info.dart';
import 'kobold_memory_rules.dart';

/// System memory one slot takes when it holds a chat of [tokens], in bytes:
/// the cache rows for those tokens, plus a hybrid model's recurrent state.
/// The engine prints the same figure rounded down ("costing N MB"):
/// Qwen3-14B, 2,388 tokens: 372; Qwen3.6-35B-A3B, 275 tokens: 68.
double smartCacheSlotBytes(
  GGUFModelInfo info, {
  required int tokens,
  double sizeFactor = 1.0,
}) {
  final perToken = (info.kvLayers ?? const <GGUFKvLayer>[]).fold(
    0,
    (sum, l) => sum + l.bytesPerCell,
  );
  final rows = info.kvLayers == null ? info.kvBytesPerToken : perToken;
  return rows * tokens * sizeFactor + info.recurrentStateBytes;
}

/// The most one slot can take, in MiB: a chat that fills the context.
int smartCacheSlotMb(
  GGUFModelInfo info, {
  required int contextSize,
  double sizeFactor = 1.0,
}) => toMibCeil(
  smartCacheSlotBytes(info, tokens: contextSize, sizeFactor: sizeFactor),
);

/// The slots KoboldCpp really makes for a preset asking for [asked].
///
/// From its source (1.122.1): 1 means its default, 5. A model with
/// recurrent layers, started with fast forward and context shift on, gets
/// smart cache whatever was asked, with one slot more (two more from four
/// up): asked 2 gives 3 (seen in a real log), asked 0 or 5 gives 7. Without
/// fast forward there is no smart cache.
int koboldSmartCacheSlots({
  required int asked,
  required bool recurrent,
  required bool fastForward,
  required bool contextShift,
}) {
  if (!fastForward) return 0;
  final limit = asked <= 1 ? 5 : asked;
  if (recurrent && contextShift) return limit + 1 + (limit >= 4 ? 1 : 0);
  return asked > 0 ? limit : 0;
}

/// Why [suggestSmartCacheSlots] chose its number.
enum SmartCacheLimit {
  /// One slot for each kind of prompt; memory was not the limit.
  promptKinds,

  /// Fewer slots than kinds of prompt: that is all the free memory allows.
  memory,

  /// No slots: the model already needs all the free memory, or more.
  noRoom,
}

/// System memory kept for everything but the model and its slots.
const int _reserveMb = 2048;

/// The most smart cache slots KoboldCpp takes.
const int kKoboldSmartCacheMaxSlots = 20;

/// The chats KoboldCpp's admin calls can save when smart cache is off: its
/// default of five slots.
const int kKoboldSaveSlots = 5;

/// How many slots to ask for: one for each kind of prompt the app sends
/// this engine ([promptKinds]: chat, the judges, a story job...), so
/// switching between them restores instead of re-reading; but only as many
/// as fit in the system memory left once the model's own share
/// ([modelRamMb]) and 2 GB for everything else are set aside.
({int slots, SmartCacheLimit limit}) suggestSmartCacheSlots({
  required int promptKinds,
  required int slotMb,
  required int freeRamMb,
  required int modelRamMb,
}) {
  final room = freeRamMb - modelRamMb - _reserveMb;
  final wanted = promptKinds.clamp(0, kKoboldSmartCacheMaxSlots);
  // A slot of unknown size is only allowed while there is room at all.
  final fit = room <= 0 ? 0 : (slotMb <= 0 ? wanted : room ~/ slotMb);
  if (fit <= 0) return (slots: 0, limit: SmartCacheLimit.noRoom);
  return fit < wanted
      ? (slots: fit, limit: SmartCacheLimit.memory)
      : (slots: wanted, limit: SmartCacheLimit.promptKinds);
}

/// What to write for [slots] wanted: the `smartcache` number and whether
/// context shift stays on.
///
/// KoboldCpp reads 1 as its default of 5, so one slot cannot be asked for.
/// A model with recurrent layers, with context shift on, gets one slot
/// more (two from four up) that it keeps for itself: one to come back to
/// after a regenerated reply, and a checkpoint part way into a long prompt.
/// A recurrent state cannot be rewound, so without those a regenerated
/// reply reads the whole chat again. Context shift itself does nothing for
/// such a model, so it is switched off only where memory has no room even
/// for KoboldCpp's smallest count (three).
({int asked, bool contextShift}) koboldSmartCacheSetting({
  required int slots,
  required bool recurrent,
}) {
  int total(int asked) => koboldSmartCacheSlots(
    asked: asked,
    recurrent: true,
    fastForward: true,
    contextShift: true,
  );
  if (!recurrent) return (asked: slots < 2 ? 0 : slots, contextShift: true);
  if (slots < total(2)) {
    return (asked: slots < 2 ? 0 : 2, contextShift: false);
  }
  var asked = 2;
  while (asked < kKoboldSmartCacheMaxSlots && total(asked + 1) <= slots) {
    asked++;
  }
  return (asked: asked, contextShift: true);
}
