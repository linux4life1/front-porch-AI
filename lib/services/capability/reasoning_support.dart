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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/capability/lmstudio_gguf.dart';
import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';

/// What a LOCAL model can actually do about thinking, read from the chat
/// template baked into its GGUF (2026-08-15).
///
/// WHY NOT THE REMOTE POKE. The remote probe learns a model's effort menu by
/// sending a bogus `reasoning.effort` and parsing the provider's
/// "Supported values are: …" 400. That works because a hosted provider
/// validates and enumerates. KoboldCpp does neither: it takes its own
/// `chat_template_kwargs.enable_thinking` + `reasoning_effort` fields and
/// simply passes them to the template, so a bogus value is ignored rather
/// than rejected. Poking it would spend a request to learn nothing AND burn
/// the "already probed" flag, so the model would never be asked again.
///
/// The answer is already on disk. In jinja mode (`--jinja`, which the managed
/// backend launches with) Kobold executes the GGUF's own chat template, and
/// that template is the thing that decides whether thinking happens at all —
/// so reading it IS reading the capability. No request, no generation, no
/// backend needed, and the same answer every time.
enum ThinkingSupport {
  /// No thinking machinery in the template — the strength chips would be
  /// decorative and the switch a no-op. Most GGUFs land here.
  none,

  /// `enable_thinking` is honoured: on/off is real, strength is not.
  toggle,

  /// `reasoning_effort` is honoured: the strength levels are real.
  graded,

  /// Thinking is emitted unconditionally with no switch to read (R1-style
  /// templates that hard-code the opening think tag). Off cannot work.
  always,
}

/// Markers that mean "this template emits a reasoning block". Deliberately
/// includes the harmony channel form — gpt-oss does not use `<think>`.
const List<String> _kThinkMarkers = [
  '<think>',
  '</think>',
  '<|channel|>analysis',
  'reasoning_content',
];

/// Read [chatTemplate] and decide what the model supports. PURE, so the whole
/// policy is a truth table over real template text.
///
/// Order is load-bearing. A gpt-oss harmony template carries BOTH
/// `reasoning_effort` and channel markers, and a Qwen3 template carries BOTH
/// `enable_thinking` and `<think>` — in each case the more specific control
/// is the honest answer, so the switches are checked before the markers.
ThinkingSupport detectThinkingFromChatTemplate(String chatTemplate) {
  if (chatTemplate.isEmpty) return ThinkingSupport.none;
  final t = chatTemplate.toLowerCase();
  if (t.contains('reasoning_effort')) return ThinkingSupport.graded;
  if (t.contains('enable_thinking')) return ThinkingSupport.toggle;
  for (final marker in _kThinkMarkers) {
    if (t.contains(marker)) return ThinkingSupport.always;
  }
  return ThinkingSupport.none;
}

/// True when the template *overwrites* `enable_thinking` to on, so a request
/// `enable_thinking:false` never reaches the render. Heretic / uncensored
/// Gemma-4 forks do this as `{%- set enable_thinking = true %}` (documented
/// in those READMEs as the way to force thinking). The Off switch still
/// exists — [thinkingBudgetClampForThinkOff] is what actually stops them.
///
/// Deliberately does NOT match `| default(true)`: that only fires when the
/// kwarg is missing, and we always send it.
final _hardOnThinkingSet = RegExp(
  r'\{%-?\s*set\s+enable_thinking\s*=\s*true\s*-?%\}',
  caseSensitive: false,
);

bool chatTemplateHardEnablesThinking(String chatTemplate) =>
    chatTemplate.isNotEmpty && _hardOnThinkingSet.hasMatch(chatTemplate);

/// The effort set [support] implies, in the app's shared vocabulary.
///
/// `toggle` and `always`-without-grading resolve to `{none}` on purpose: the
/// shared [reasoningEffortChipsFor] drops `none` and every unranked entry, so
/// an empty chip row falls out by construction rather than by a second rule
/// somewhere in the UI. A model with no strength levels should show no
/// strength chips.
Set<String> effortsForThinkingSupport(ThinkingSupport support) =>
    switch (support) {
      ThinkingSupport.graded => const {'none', 'low', 'medium', 'high'},
      ThinkingSupport.toggle ||
      ThinkingSupport.always ||
      ThinkingSupport.none => const {'none'},
    };

/// oMLX `/v1/models/status` + the on-disk chat template. PURE.
///
/// oMLX does not reject a bogus `reasoning_effort` (no listing 400) and has
/// no `/props` chat-template endpoint — poking it would load the model.
/// The template lives next to the weights (`chat_template.jinja`), and the
/// status row already gives us `model_path` plus `thinking_default`.
///
/// `thinking_default` is a bool when oMLX classified the model as having a
/// thinking mode (true = on by default, false = off by default) and null
/// when it did not. A classified model whose template is silent still has
/// an engine-level on/off (`enable_thinking`), so that case is `toggle`.
/// A more specific template verdict (graded / toggle / always) always wins.
ThinkingSupport? detectThinkingFromOmlxEntry({
  required String? chatTemplate,
  required Object? thinkingDefault,
}) {
  final classified = thinkingDefault is bool;
  if (chatTemplate != null && chatTemplate.isNotEmpty) {
    final fromTemplate = detectThinkingFromChatTemplate(chatTemplate);
    if (fromTemplate == ThinkingSupport.none && classified) {
      return ThinkingSupport.toggle;
    }
    return fromTemplate;
  }
  return classified ? ThinkingSupport.toggle : null;
}

/// One cached thinking verdict per local model file, mirroring
/// [VisionSupportResolver]'s GGUF half: parse once, cache by path (including
/// the misses, so a torn file is not re-read on every rebuild), and register
/// the result into the SHARED reasoning-effort store so the existing chip and
/// caption machinery applies to local models without a second code path.
///
/// Registrations pass `persist: false`: the on-disk menu store is for remote
/// models learned from a provider, and a local file path is neither portable
/// nor worth persisting — the GGUF is re-read for free next launch.
class ReasoningSupportResolver {
  ReasoningSupportResolver._();
  static final ReasoningSupportResolver instance = ReasoningSupportResolver._();

  final Map<String, ThinkingSupport?> _cache = {};
  final Map<String, Future<ThinkingSupport?>> _inFlight = {};

  /// Seam for tests to substitute a mock HTTP client. Production always
  /// creates a real client per request.
  @visibleForTesting
  http.Client Function() httpClientFactory = http.Client.new;

  // Deliberately NO notifier of its own: registering the verdict below bumps
  // the shared kReasoningEffortCatalogTick, which Settings already listens to.
  // A second notification path would be one more thing to keep in sync.

  /// The verdict for [key] if it has already been resolved. Safe to call
  /// from a build path — it never touches disk or the network.
  ///
  /// [key] is the GGUF path for KoboldCpp, or the oMLX model id.
  ThinkingSupport? peek(String key) => _cache[key];

  bool isResolved(String key) => _cache.containsKey(key);

  /// Parse (and cache) the thinking capability of a local GGUF.
  ///
  /// Never call this from a build path: it reads the file. Callers kick it
  /// from a lifecycle hook and read [peek] afterwards.
  Future<ThinkingSupport?> resolveLocalGguf(String modelPath) async {
    if (modelPath.isEmpty) return null;
    if (_cache.containsKey(modelPath)) return _cache[modelPath];

    ThinkingSupport? support;
    String? template;
    try {
      template = await readChatTemplate(modelPath);
      if (template != null) {
        support = detectThinkingFromChatTemplate(template);
      }
    } catch (_) {
      support = null; // unreadable file → unknown, chips stay generic
    }
    _cache[modelPath] = support;
    if (support != null) {
      _remember(modelPath, support, chatTemplate: template);
    }
    return support;
  }

  /// Resolve an oMLX model's thinking support from `/v1/models/status`
  /// plus the on-disk template at `model_path`. Never generates, never
  /// loads the model. [apiUrl] is the OpenAI base (`http://localhost:8000/v1`).
  ///
  /// A failed fetch is NOT cached — the server may be down or still
  /// starting. A successful fetch that cannot decide caches `null` so a
  /// missing template is not re-read every rebuild.
  Future<ThinkingSupport?> resolveOmlx({
    required String apiUrl,
    required String modelName,
    String apiKey = '',
  }) {
    if (modelName.isEmpty || apiUrl.isEmpty) return Future.value(null);
    if (_cache.containsKey(modelName)) {
      return Future.value(_cache[modelName]);
    }
    final pending = _inFlight[modelName];
    if (pending != null) return pending;
    final run = _resolveOmlx(
      apiUrl: apiUrl,
      modelName: modelName,
      apiKey: apiKey,
    );
    _inFlight[modelName] = run;
    return run.whenComplete(() => _inFlight.remove(modelName));
  }

  Future<ThinkingSupport?> _resolveOmlx({
    required String apiUrl,
    required String modelName,
    required String apiKey,
  }) async {
    final entry = await _fetchOmlxStatusEntry(
      apiUrl: apiUrl,
      modelName: modelName,
      apiKey: apiKey,
    );
    if (entry == null) return null; // no verdict — no cache

    final path = entry['model_path']?.toString() ?? '';
    String? template;
    if (path.isNotEmpty) {
      template = await readChatTemplateFromModelDir(path);
    }
    final support = detectThinkingFromOmlxEntry(
      chatTemplate: template,
      thinkingDefault: entry['thinking_default'],
    );
    _cache[modelName] = support;
    if (support != null) {
      _remember(modelName, support, chatTemplate: template);
    }
    return support;
  }

  Future<Map<dynamic, dynamic>?> _fetchOmlxStatusEntry({
    required String apiUrl,
    required String modelName,
    required String apiKey,
  }) async {
    final uri = originEndpointUri(apiUrl, 'v1/models/status');
    if (uri == null) return null;
    final client = httpClientFactory();
    try {
      final response = await client
          .get(
            uri,
            headers: {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final models = decoded['models'];
      if (models is! List) return null;
      for (final entry in models) {
        if (entry is! Map) continue;
        if ((entry['id'] ?? '').toString() == modelName) return entry;
      }
      return null;
    } catch (e) {
      debugPrint('[ReasoningSupport] oMLX status fetch failed ($uri): $e');
      return null;
    } finally {
      client.close();
    }
  }

  void _remember(String key, ThinkingSupport support, {String? chatTemplate}) {
    rememberReasoningEffortsForModel(
      key,
      effortsForThinkingSupport(support),
      persist: false,
    );
    if (support == ThinkingSupport.always) {
      rememberMandatoryReasoning(key, persist: false);
    }
    // Hard-on is independent of the verdict: a heretic Gemma template still
    // *mentions* enable_thinking (so it is `toggle` — Off stays in the UI)
    // while the `{% set %}` makes the kwarg a no-op.
    if (chatTemplate != null && chatTemplateHardEnablesThinking(chatTemplate)) {
      rememberHardOnThinking(key);
    } else {
      forgetHardOnThinking(key);
    }
  }

  /// Resolve an LM Studio model's thinking support from `/api/v0/models`
  /// plus the on-disk GGUF. Never generates — a completions poke JIT-loads
  /// the model (verified 2026-08-15 against 0.4.21) and the 400 listing is
  /// the *server's* parameter enum, not this model's capability.
  Future<ThinkingSupport?> resolveLmStudio({
    required String apiUrl,
    required String modelName,
    String apiKey = '',
  }) {
    if (modelName.isEmpty || apiUrl.isEmpty) return Future.value(null);
    if (_cache.containsKey(modelName)) {
      return Future.value(_cache[modelName]);
    }
    final pending = _inFlight[modelName];
    if (pending != null) return pending;
    final run = _resolveLmStudio(
      apiUrl: apiUrl,
      modelName: modelName,
      apiKey: apiKey,
    );
    _inFlight[modelName] = run;
    return run.whenComplete(() => _inFlight.remove(modelName));
  }

  Future<ThinkingSupport?> _resolveLmStudio({
    required String apiUrl,
    required String modelName,
    required String apiKey,
  }) async {
    final entry = await _fetchLmStudioModelEntry(
      apiUrl: apiUrl,
      modelName: modelName,
      apiKey: apiKey,
    );
    if (entry == null) return null; // not LMS / down / unknown id — no cache

    final root = lmStudioModelsRoot();
    String? template;
    if (root != null) {
      final gguf = await findLmStudioGguf(
        modelsRoot: root,
        modelId: modelName,
        publisher: entry['publisher']?.toString(),
        quantization: entry['quantization']?.toString(),
      );
      if (gguf != null) template = await readChatTemplate(gguf);
    }
    final support = template == null
        ? null
        : detectThinkingFromChatTemplate(template);
    _cache[modelName] = support;
    if (support != null) {
      _remember(modelName, support, chatTemplate: template);
    }
    return support;
  }

  Future<Map<dynamic, dynamic>?> _fetchLmStudioModelEntry({
    required String apiUrl,
    required String modelName,
    required String apiKey,
  }) async {
    final uri = originEndpointUri(apiUrl, 'api/v0/models');
    if (uri == null) return null;
    final client = httpClientFactory();
    try {
      final response = await client
          .get(
            uri,
            headers: {if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final data = decoded['data'];
      if (data is! List) return null;
      for (final entry in data) {
        if (entry is! Map) continue;
        if ((entry['id'] ?? '').toString() != modelName) continue;
        // LM Studio's /api/v0 listing carries these; a generic OpenAI
        // /v1/models 200 would not. Refuse to claim a verdict from that.
        if (entry['state'] == null && entry['compatibility_type'] == null) {
          return null;
        }
        return entry;
      }
      return null;
    } catch (e) {
      debugPrint('[ReasoningSupport] LM Studio listing failed ($uri): $e');
      return null;
    } finally {
      client.close();
    }
  }

  /// Test seam: drop every verdict so a suite can resolve the same key twice.
  @visibleForTesting
  void clearForTest() {
    _cache.clear();
    _inFlight.clear();
    httpClientFactory = http.Client.new;
  }
}

/// Pull `tokenizer.chat_template` out of a GGUF header.
///
/// Reuses [GGUFFileReader.parseMetadataBytes], which already skips the huge
/// token array by length arithmetic instead of decoding it — so this costs one
/// bounded header read and no allocation per token. Returns null when the file
/// is missing, is not a GGUF, or carries no template (llama.cpp then falls back
/// to its built-in adapter, and no template means no thinking machinery we can
/// read).
Future<String?> readChatTemplate(String modelPath) async {
  final file = File(modelPath);
  if (!await file.exists()) return null;
  final raf = await file.open(mode: FileMode.read);
  try {
    // Same bounded window the vision parser uses: the metadata header sits at
    // the very front of the file, well inside this.
    final bytes = await raf.read(4 * 1024 * 1024);
    final meta = GGUFFileReader.parseMetadataBytes(bytes);
    final template = meta?['tokenizer.chat_template'];
    return template is String && template.isNotEmpty ? template : null;
  } catch (_) {
    return null;
  } finally {
    await raf.close();
  }
}

/// Read the chat template out of an MLX / HuggingFace model directory.
/// Prefers `chat_template.jinja` (the file oMLX models actually ship) over
/// `tokenizer_config.json`'s `chat_template` field. Never opens
/// `tokenizer.json` — that file is tens of megabytes of token data.
Future<String?> readChatTemplateFromModelDir(String modelPath) async {
  if (modelPath.isEmpty) return null;
  try {
    final jinja = File(p.join(modelPath, 'chat_template.jinja'));
    if (await jinja.exists()) {
      final text = await jinja.readAsString();
      if (text.isNotEmpty) return text;
    }
    final config = File(p.join(modelPath, 'tokenizer_config.json'));
    if (!await config.exists()) return null;
    final decoded = jsonDecode(await config.readAsString());
    if (decoded is Map) {
      final template = decoded['chat_template'];
      if (template is String && template.isNotEmpty) return template;
    }
  } catch (_) {
    return null;
  }
  return null;
}
