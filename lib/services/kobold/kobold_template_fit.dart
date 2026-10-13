// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/utils/gguf_reader.dart';

/// Turn markers a chat template writes: `<|im_start|>`, `<｜User｜>`,
/// `<start_of_turn>`, `[INST]`. Pipe markers are never ordinary text, so a
/// model that lacks one cannot read the template. Angle and bracket markers
/// can be plain text in an older vocabulary (Llama 2 writes `[INST]` as
/// letters), so they only count against a model whose vocabulary has
/// markers of that shape.
final _pipe = RegExp(r'<\|[^|<>\s]{1,48}\|>');
final _wide = RegExp(r'<｜[^｜<>]{1,48}｜>');
final _angle = RegExp(r'</?[a-z][a-z0-9_]{0,31}>');
final _bracket = RegExp(r'\[/?[A-Z][A-Z_]{1,31}\]');

/// How much of a GGUF is read for its vocabulary and embedded template. The
/// metadata sits at the front; a 262k-token vocabulary is a few megabytes.
const int _kVocabWindow = 48 * 1024 * 1024;

/// The turn markers written in [template].
Set<String> chatTemplateMarkers(String template) => {
  for (final re in [_pipe, _wide, _angle, _bracket])
    for (final m in re.allMatches(template)) m.group(0)!,
};

bool _whole(RegExp re, String text) => re.stringMatch(text) == text;

bool _isMarker(String token) =>
    [_pipe, _wide, _angle, _bracket].any((re) => _whole(re, token));

/// Why a picked template may not fit a model: it [fits] when nothing is
/// [missing] and it shares a marker with the model's own template.
class ChatTemplateFit {
  const ChatTemplateFit({required this.missing, required this.modelMarkers});

  /// Markers the template writes that the model's vocabulary does not have.
  final List<String> missing;

  /// The model's own template markers, when the picked template shares none
  /// of them. Empty when they overlap or the model embeds no template.
  final List<String> modelMarkers;

  bool get fits => missing.isEmpty && modelMarkers.isEmpty;

  String message(String modelName) => missing.isNotEmpty
      ? 'This template may not fit $modelName. It writes '
            '${missing.take(3).join(', ')}, which the model does not know.'
      : 'This template may not fit $modelName. The model\'s own template '
            'uses ${modelMarkers.take(3).join(', ')} and this one does not.';

  Map<String, dynamic> toJson(String modelName) => {
    'message': message(modelName),
    'missing': missing,
    'modelMarkers': modelMarkers,
  };
}

/// Compares [template] with a model's marker tokens ([vocab], null when the
/// vocabulary could not be read whole) and its [embedded] template.
ChatTemplateFit checkChatTemplateFit({
  required String template,
  Set<String>? vocab,
  String? embedded,
}) {
  final picked = chatTemplateMarkers(template);
  final missing = <String>[];
  if (vocab != null) {
    bool shaped(RegExp re) => vocab.any((t) => _whole(re, t));
    final angle = shaped(_angle);
    final bracket = shaped(_bracket);
    for (final marker in picked) {
      if (vocab.contains(marker)) continue;
      final decisive =
          _whole(_pipe, marker) ||
          _whole(_wide, marker) ||
          (angle && _whole(_angle, marker)) ||
          (bracket && _whole(_bracket, marker));
      if (decisive) missing.add(marker);
    }
  }
  final own = embedded == null ? <String>{} : chatTemplateMarkers(embedded);
  final clash =
      picked.isNotEmpty && own.isNotEmpty && picked.intersection(own).isEmpty;
  return ChatTemplateFit(
    missing: missing..sort(),
    modelMarkers: clash ? (own.toList()..sort()) : const [],
  );
}

/// A model's marker tokens and embedded template, read once per file.
typedef _ModelFacts = ({Set<String>? vocab, String? embedded});
final Map<String, ({String stamp, _ModelFacts facts})> _modelCache = {};

Future<_ModelFacts?> _modelFacts(String modelPath) async {
  final file = File(modelPath);
  final FileStat stat;
  try {
    stat = await file.stat();
  } on FileSystemException catch (e) {
    debugPrint('[Template] model unreadable for the template check: $e');
    return null;
  }
  if (stat.type != FileSystemEntityType.file) return null;
  final stamp = '${stat.size}:${stat.modified.millisecondsSinceEpoch}';
  final known = _modelCache[modelPath];
  if (known != null && known.stamp == stamp) return known.facts;
  final facts = await Isolate.run(() => _readModelFacts(modelPath));
  if (facts != null) _modelCache[modelPath] = (stamp: stamp, facts: facts);
  return facts;
}

Future<_ModelFacts?> _readModelFacts(String modelPath) async {
  final raf = await File(modelPath).open();
  try {
    final bytes = await raf.read(_kVocabWindow);
    final kept = <String>{};
    var seen = 0;
    final header = GGUFFileReader.parseHeaderBytes(
      bytes,
      onToken: (token) {
        seen++;
        if (_isMarker(token)) kept.add(token);
      },
    );
    if (header == null) return null;
    final total = header.meta['tokenizer.ggml.tokens'];
    final embedded = header.meta['tokenizer.chat_template'];
    return (
      // A vocabulary cut off by the window would report real markers missing.
      vocab: total is int && total > 0 && seen == total ? kept : null,
      embedded: embedded is String && embedded.isNotEmpty ? embedded : null,
    );
  } finally {
    await raf.close();
  }
}

/// What a template is remembered by: its exact text.
String _templateId(List<int> bytes) => '${sha256.convert(bytes)}';

/// What a model is remembered by: its file name and size, so a model moved
/// to another folder is still the same model.
Future<String> _modelId(String modelPath) async =>
    '${p.basename(modelPath)}:${await File(modelPath).length()}';

File _acceptedFile(String engineDir) =>
    File(p.join(engineDir, 'chat_templates', 'accepted.json'));

Future<Set<String>> _accepted(String engineDir) async {
  final file = _acceptedFile(engineDir);
  if (!await file.exists()) return {};
  try {
    final decoded = jsonDecode(await file.readAsString());
    return decoded is List ? {for (final e in decoded) '$e'} : {};
  } on FormatException catch (e) {
    debugPrint('[Template] accepted list unreadable, starting over: $e');
    return {};
  }
}

/// The warning to show for [templatePath] on [modelPath], or null when the
/// template fits, was accepted for this model, or cannot be checked (no
/// template, no model, or a file that cannot be read).
Future<ChatTemplateFit?> koboldTemplateWarning({
  required String engineDir,
  required String templatePath,
  required String modelPath,
}) async {
  if (templatePath.isEmpty || modelPath.isEmpty) return null;
  try {
    final bytes = await File(templatePath).readAsBytes();
    final model = await _modelFacts(modelPath);
    if (model == null) return null;
    final fit = checkChatTemplateFit(
      template: utf8.decode(bytes, allowMalformed: true),
      vocab: model.vocab,
      embedded: model.embedded,
    );
    if (fit.fits) return null;
    final key = '${_templateId(bytes)}|${await _modelId(modelPath)}';
    return (await _accepted(engineDir)).contains(key) ? null : fit;
  } on Object catch (e) {
    // The check only advises: a file it cannot read means no warning.
    debugPrint('[Template] template check skipped: $e');
    return null;
  }
}

/// Remembers that [templatePath] is wanted on [modelPath] despite a
/// warning, so the same pair is not asked about again. A different template
/// or model asks again.
Future<void> acceptKoboldTemplate({
  required String engineDir,
  required String templatePath,
  required String modelPath,
}) async {
  final key =
      '${_templateId(await File(templatePath).readAsBytes())}|'
      '${await _modelId(modelPath)}';
  final accepted = await _accepted(engineDir)
    ..add(key);
  final file = _acceptedFile(engineDir);
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(accepted.toList()..sort()), flush: true);
}
