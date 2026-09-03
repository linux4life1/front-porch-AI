// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// App-facing thinking strength and how it maps onto whatever ladder a
// remote model actually accepts. The chip row is that model's kitchen
// menu — not a fixed Low/Medium/High card we then remap.

import 'package:flutter/foundation.dart';

/// Fallback chips when we have not yet learned this model's menu.
const List<String> kAppReasoningEfforts = ['low', 'medium', 'high'];

/// Full ladder any provider has used (for nearest-match math).
const Map<String, int> kReasoningEffortRank = {
  'none': 0,
  'minimal': 1,
  'low': 2,
  'medium': 3,
  'high': 4,
  'xhigh': 5,
  'max': 6,
};

/// Short display title for a strength id.
String reasoningEffortTitle(String id) => switch (id) {
  'none' => 'Off',
  'minimal' => 'Minimal',
  'low' => 'Low',
  'medium' => 'Medium',
  'high' => 'High',
  'xhigh' => 'Extra high',
  'max' => 'Max',
  _ => id,
};

/// One-line blurb under a strength chip.
String reasoningEffortBlurb(String id) => switch (id) {
  'low' => 'Light think — faster, cheaper',
  'medium' => 'Balanced — default',
  'high' => 'Deep think — slower, richer',
  'xhigh' => 'Heavier than high',
  'max' => 'Full thinking budget',
  'none' => 'No thinking tokens',
  'minimal' => 'Bare-minimum thinking',
  _ => '',
};

/// Models whose provider taught us a supported set (process lifetime).
final Map<String, Set<String>> kLearnedReasoningEffortsByModel =
    <String, Set<String>>{};

/// Bumped when the learned menu changes so Settings can redraw chips.
final ValueNotifier<int> kReasoningEffortCatalogTick = ValueNotifier<int>(0);

void _bumpReasoningEffortCatalog() {
  if (_catalogBatchDepth == 0) kReasoningEffortCatalogTick.value++;
}

int _catalogBatchDepth = 0;

/// Hold tick notifications across a /models seed (one redraw at the end).
void beginReasoningEffortCatalogBatch() => _catalogBatchDepth++;

/// True while [beginReasoningEffortCatalogBatch] is open (persist no-ops).
bool get reasoningEffortCatalogIsBatching => _catalogBatchDepth > 0;

void Function()? persistReasoningEffortMenusFlushHook;

void endReasoningEffortCatalogBatch() {
  if (_catalogBatchDepth == 0) return;
  _catalogBatchDepth--;
  if (_catalogBatchDepth == 0) {
    kReasoningEffortCatalogTick.value++;
    persistReasoningEffortMenusFlushHook?.call();
  }
}

/// Loopback / RFC1918 / Tailscale CGNAT / .local — do not poke these.
bool isLocalRemoteUrl(String url) {
  final host = (Uri.tryParse(url)?.host ?? '').toLowerCase();
  if (host.isEmpty) return false;
  if (host == 'localhost' ||
      host == '127.0.0.1' ||
      host == '0.0.0.0' ||
      host == '::1') {
    return true;
  }
  if (host.endsWith('.local')) return true;
  if (host.startsWith('192.168.') || host.startsWith('10.')) return true;
  if (RegExp(r'^172\.(1[6-9]|2\d|3[0-1])\.').hasMatch(host)) return true;
  // 100.64.0.0/10 (Tailscale)
  if (RegExp(r'^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.').hasMatch(host)) {
    return true;
  }
  return false;
}

/// Models that reject turning thinking off (catalog `mandatory` or a 400).
final Set<String> kMandatoryReasoningModels = <String>{};

/// Local models whose chat template `{% set enable_thinking = true %}` so
/// a request `enable_thinking:false` is overwritten at render. Off still
/// works: local servers that honour llama.cpp / oMLX `thinking_budget`
/// force-close the think block at 0 tokens. Keyed by oMLX/LMS model id
/// or the Kobold GGUF path — same keys [ReasoningSupportResolver] uses.
final Set<String> kHardOnThinkingModels = <String>{};

/// DeepSeek-on-Nano `:thinking` 400: none / high / max (Discord 2026-07-18).
/// Same pair is GLM-5.2's native ladder (Together / Z.ai). Not a universal
/// `:thinking` menu — that suffix is Nano's "use the thinking variant" tag.
const Set<String> kHighMaxEffortHint = {'none', 'high', 'max'};

/// Kimi K2.6 official: low / high / max; thinking can be switched off.
const Set<String> kLowHighMaxEffortHint = {'none', 'low', 'high', 'max'};

/// Family hints only. `:thinking` alone is not a ladder.
Set<String>? reasoningEffortHintForModel(String model) {
  final id = model.toLowerCase();
  if (id.contains('deepseek') && id.contains(':thinking')) {
    return kHighMaxEffortHint;
  }
  if (id.contains('glm-5.2') || id.contains('glm5.2')) {
    return kHighMaxEffortHint;
  }
  if (id.contains('kimi-k2.6') || id.contains('kimi-k2-6')) {
    return kLowHighMaxEffortHint;
  }
  return null;
}

/// Supported set for [model]: learned / catalog > family hint > null.
Set<String>? reasoningEffortSupportedFor(String model) {
  if (model.isEmpty) return null;
  return kLearnedReasoningEffortsByModel[model] ??
      reasoningEffortHintForModel(model);
}

/// Closest supported stand-in. Keeps thinking ON — never maps to `none` when
/// any thinking tier exists.
String nearestReasoningEffort(String requested, Set<String> supported) {
  if (supported.contains(requested)) return requested;
  final req =
      kReasoningEffortRank[requested] ?? kReasoningEffortRank['medium']!;
  final thinking = supported.where((s) => s != 'none');
  final pool = (thinking.isNotEmpty ? thinking : supported).where(
    kReasoningEffortRank.containsKey,
  );
  if (pool.isEmpty) return requested;
  return pool.reduce((a, b) {
    final da = (kReasoningEffortRank[a]! - req).abs();
    final db = (kReasoningEffortRank[b]! - req).abs();
    if (da != db) return da < db ? a : b;
    return kReasoningEffortRank[a]! < kReasoningEffortRank[b]! ? a : b;
  });
}

/// Value that will go on the wire for [model] given the user's [requested].
String wireReasoningEffort(String model, String requested) {
  final supported = reasoningEffortSupportedFor(model);
  if (supported == null) return requested;
  // Toggle-only ({none}): effort is not a real ladder. Never rewrite the
  // user's pick to `none` while thinking is on — that would disable thinking
  // on hosts that map effort none → off (NanoGPT / OpenRouter).
  final thinking = supported.where((s) => s != 'none');
  if (thinking.isEmpty) return requested;
  return nearestReasoningEffort(requested, supported);
}

/// llama.cpp / LM Studio / OpenAI-compat **server enum**, not a per-model
/// menu. Live LMS 0.4.21: `none, minimal, low, medium, high, xhigh`.
/// DeepSeek/Kimi listings never pair `minimal` with `xhigh`.
bool isGenericProviderEffortSchema(Set<String> listing) =>
    listing.contains('minimal') && listing.contains('xhigh');

/// Learned `{none}` (or only none): on/off, no strength chips. Same shape
/// oMLX writes for a template `toggle` verdict.
bool reasoningEffortIsToggleOnly(String model) {
  final supported = reasoningEffortSupportedFor(model);
  if (supported == null || supported.isEmpty) return false;
  return supported.every((s) => s == 'none');
}

/// True when this model rejects turning thinking off.
bool reasoningEffortIsMandatory(String model) =>
    model.isNotEmpty && kMandatoryReasoningModels.contains(model);

/// Models that 400 `reasoning.enabled=false` even before we have learned
/// them. Kimi's thinking variants did this live on 2026-08-08 and again
/// on kimi-k2.6:thinking 2026-08-15. Used on the wire so the first eval
/// of a session does not spend a 400; the Off switch still waits for a
/// real 400 before locking (the effort hint still lists `none`).
bool reasoningCannotDisable(String model) {
  if (reasoningEffortIsMandatory(model)) return true;
  final id = model.toLowerCase();
  return id.contains('kimi') && id.contains('thinking');
}

/// User asked for thinking, or the model will not allow Off.
bool reasoningEffortThinkingOn(String model, bool requested) =>
    requested || reasoningEffortIsMandatory(model);

/// Extra `max_tokens` headroom for EVAL calls (salvageReasoning) on a model
/// whose thinking cannot be switched off. Mandatory reasoning counts against
/// `max_tokens`, and the evals cap at 4000 — Kimi 2.6:thinking regularly
/// thinks past that on the fused one-shot prompt, so the stream was cut
/// mid-think (finish_reason=length) and the final JSON / tool call never
/// arrived: bond_delta=null on some turns and not others, purely on how long
/// the model happened to deliberate (live repro 2026-08-15, a 17,348-char
/// think ≈ the 4000-token cap exactly). The cap is a runaway guard, not a
/// spend — billing follows actual tokens generated.
const int kMandatoryReasoningThinkHeadroomTokens = 16000;

/// Thinking-on chips for [model], weakest → strongest. Unknown → Low/Med/High.
List<String> reasoningEffortChipsFor(String model) {
  final supported = reasoningEffortSupportedFor(model);
  if (supported == null) return List<String>.from(kAppReasoningEfforts);
  final chips =
      supported
          .where((s) => s != 'none' && kReasoningEffortRank.containsKey(s))
          .toList()
        ..sort(
          (a, b) =>
              kReasoningEffortRank[a]!.compareTo(kReasoningEffortRank[b]!),
        );
  if (chips.isEmpty) return const <String>[];
  return chips;
}

/// Highlight a real chip. Old saved Low/Medium snap to the nearest live one.
String reasoningEffortDisplayedSelection(String model, String requested) {
  final chips = reasoningEffortChipsFor(model);
  if (chips.contains(requested)) return requested;
  return nearestReasoningEffort(
    requested.isEmpty ? 'medium' : requested,
    chips.toSet(),
  );
}

/// User-facing caption: this model's real menu (and Off, if locked).
String reasoningEffortMappingCaption(String model, String requested) {
  if (model.isEmpty) return '';
  final chips = reasoningEffortChipsFor(model);
  final allowed = chips.map(reasoningEffortTitle).join(' · ');
  if (reasoningEffortIsMandatory(model)) {
    return 'This model always thinks. Strengths: $allowed.';
  }
  final supported = reasoningEffortSupportedFor(model);
  if (supported == null) {
    if (requested.isEmpty) return '';
    return 'Sent as ${reasoningEffortTitle(requested).toLowerCase()}. '
        'When we know this model\'s levels, the chips match them.';
  }
  return 'This model\'s thinking levels: $allowed.';
}

/// Parse "Supported values are: none, high, max" from a provider error body.
Set<String>? supportedReasoningEffortsFromError(String msg) {
  final m = msg.toLowerCase();
  if (!m.contains('reasoning.effort') &&
      !m.contains('reasoning effort') &&
      !m.contains('reasoning_effort')) {
    return null;
  }
  final listing = m.indexOf('supported values');
  if (listing < 0) return null;
  final colon = m.indexOf(':', listing);
  if (colon < 0) return null;
  final values = RegExp(r'[a-z]+')
      .allMatches(m.substring(colon + 1))
      .map((x) => x.group(0)!)
      .where(kReasoningEffortRank.containsKey)
      .toSet();
  return values.isEmpty ? null : values;
}

/// Remember a provider's supported set for [model] (process + disk).
void rememberReasoningEffortsForModel(
  String model,
  Set<String> supported, {
  bool persist = true,
}) {
  if (model.isEmpty || supported.isEmpty) return;
  kLearnedReasoningEffortsByModel[model] = Set<String>.from(supported);
  _bumpReasoningEffortCatalog();
  if (persist) persistReasoningEffortMenuHook?.call(model, probed: false);
}

/// Remember that [model] cannot turn thinking off.
void rememberMandatoryReasoning(String model, {bool persist = true}) {
  if (model.isEmpty) return;
  if (kMandatoryReasoningModels.add(model)) {
    _bumpReasoningEffortCatalog();
    if (persist) persistReasoningEffortMenuHook?.call(model, probed: true);
  }
}

/// Remember that [model]'s template hard-sets thinking on. Never persisted
/// — a local path / oMLX id is not portable, and the template is re-read
/// next launch.
void rememberHardOnThinking(String model) {
  if (model.isEmpty) return;
  if (kHardOnThinkingModels.add(model)) _bumpReasoningEffortCatalog();
}

void forgetHardOnThinking(String model) {
  if (model.isEmpty) return;
  if (kHardOnThinkingModels.remove(model)) _bumpReasoningEffortCatalog();
}

/// True when this model's jinja overwrites `enable_thinking` to on.
bool reasoningTemplateForcesThinking(String model) =>
    model.isNotEmpty && kHardOnThinkingModels.contains(model);

/// `thinking_budget: 0` when the app asked for thinking off on a local
/// model whose jinja would ignore `enable_thinking:false`, or null to omit.
///
/// [thinkOn] is the same bit the payload already uses (`reasoningEnabled &&
/// reasoningMaxTokens != 0`). Continue, call mode, and every eval pass
/// false; a normal reply with Request thinking on passes true and is
/// untouched. Sending 0 on a stock Gemma-4 that already honours the kwarg
/// attaches oMLX's closer processor and can leak a second `<channel|>`
/// into the answer, so this is also gated on
/// [reasoningTemplateForcesThinking].
int? thinkingBudgetClampForThinkOff(String model, {required bool thinkOn}) {
  if (thinkOn) return null;
  if (!reasoningTemplateForcesThinking(model)) return null;
  return 0;
}

/// Wired by [attachReasoningEffortMenuStore] so this file does not import disk.
void Function(String model, {required bool probed})?
persistReasoningEffortMenuHook;

/// Seed from an OpenRouter (or similar) `reasoning` catalog object.
void rememberReasoningProfileFromCatalog(String model, Object? reasoning) {
  if (model.isEmpty || reasoning is! Map) return;
  final raw = reasoning['supported_efforts'];
  if (raw is List) {
    final set = raw
        .map((e) => e.toString().toLowerCase())
        .where(kReasoningEffortRank.containsKey)
        .toSet();
    if (set.isNotEmpty) rememberReasoningEffortsForModel(model, set);
  }
  if (reasoning['mandatory'] == true) {
    rememberMandatoryReasoning(model);
  } else if (reasoning.containsKey('mandatory') &&
      kMandatoryReasoningModels.remove(model)) {
    _bumpReasoningEffortCatalog();
    persistReasoningEffortMenuHook?.call(model, probed: false);
  }
}

/// Test helper: drop process-lifetime catalog state.
void clearReasoningEffortCatalog() {
  kLearnedReasoningEffortsByModel.clear();
  kMandatoryReasoningModels.clear();
  kHardOnThinkingModels.clear();
  _bumpReasoningEffortCatalog();
}
