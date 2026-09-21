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

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/worker_backend.dart';

/// App-owned `--admindir` so reload_config can see GGUF + `.kcpps` names.
String koboldAdminDirFor(StorageService storage) {
  final root = storage.rootPath?.trim() ?? '';
  if (root.isNotEmpty) return p.join(root, 'kobold_admin');
  return p.join(storage.modelsDir.path, 'kobold_admin');
}

/// KoboldCpp `POST /api/admin/reload_config` body.
///
/// Documented: `filename` is `unload_model`, `initial_model`, a GGUF, or a
/// `.kcpps` inside `--admindir`. `overrideconfig` / `baseconfig` attaches a
/// different `.kcpps` to a GGUF without killing our process.
///
/// Kobold does not retarget the parent argv `--config` from HTTP. The
/// least-cache-destructive change it exposes is this reload: it tears
/// down `kcpp_instance` inside the same parent (SWA slots on a full
/// binary restart are gone). Empty GGUF + different `.kcpps` uses the
/// `.kcpps` as `filename`. Worker `.kcpps` embedding mmproj via
/// `--config` stays parked (no worker mmproj picker).
Map<String, String> koboldAdminReloadBody({
  required String filename,
  String overrideConfig = '',
}) {
  final body = <String, String>{'filename': filename};
  if (overrideConfig.trim().isNotEmpty) {
    body['overrideconfig'] = overrideConfig.trim();
  }
  return body;
}

/// Filename sent for an in-process load. Empty GGUF + same `.kcpps` as
/// last start → `initial_model`. A different `.kcpps` uses that file's name.
/// A GGUF uses the basename (override carries the `.kcpps`).
String koboldAdminLoadFilename({
  required String requestedModel,
  required String requestedKcpps,
  String launchedKcpps = '',
}) {
  final model = requestedModel.trim();
  if (model.isNotEmpty) return p.basename(model);
  final kcpps = requestedKcpps.trim();
  if (kcpps.isNotEmpty &&
      normalizeLocalModelPath(kcpps) !=
          normalizeLocalModelPath(launchedKcpps)) {
    return p.basename(kcpps);
  }
  return 'initial_model';
}

/// `overrideconfig` when a GGUF load also needs a different `.kcpps`.
String koboldAdminLoadOverride({
  required String requestedModel,
  required String requestedKcpps,
}) {
  if (requestedModel.trim().isEmpty) return '';
  final kcpps = requestedKcpps.trim();
  if (kcpps.isEmpty) return '';
  return p.basename(kcpps);
}

/// HTTP 200 is not enough: Kobold still returns 200 with `success: false`
/// when `--admin` / `--admindir` is missing. The live miss was
/// `Kobold admin unload_model HTTP 200` because we required
/// `body is Map && body['success'] == true` (bool only) — empty ACK,
/// JSON `true`, and `"true"` all threw and restarted the process.
///
/// Accept 2xx + truthy `success`, string `"true"`, JSON `true`, a map
/// with no `success` key, and an empty 200. Reject `success: false`.
bool koboldAdminReloadSucceeded(int statusCode, String body) {
  if (statusCode < 200 || statusCode >= 300) return false;
  final trimmed = body.trim();
  if (trimmed.isEmpty) return true;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map) {
      if (!decoded.containsKey('success')) return true;
      return koboldAdminSuccessFlag(decoded['success']);
    }
    return koboldAdminSuccessFlag(decoded);
  } catch (_) {
    return koboldAdminSuccessFlag(trimmed);
  }
}

/// Kobold uses a JSON bool on reload_config; other admin routes use `"true"`.
bool koboldAdminSuccessFlag(Object? value) {
  if (value == true || value == 1) return true;
  if (value == false || value == 0 || value == null) return false;
  final s = value.toString().trim().toLowerCase();
  return s == 'true' || s == '1' || s == 'yes';
}

/// Tiny non-stream completion that proves a swapped GGUF can generate.
/// `/api/extra/version` 200 is HTTP-up only — not this.
Map<String, dynamic> koboldGenerationReadyPayload() => {
  'model': 'kobold',
  'stream': false,
  'max_tokens': 1,
  'temperature': 0,
  'messages': [
    {'role': 'user', 'content': 'ok'},
  ],
};

/// True only when a completion actually produced assistant text.
/// Version JSON, empty/newline content, and 0-token usage are FAIL.
bool koboldCompletionIsGenerationReady(int statusCode, String body) {
  if (statusCode < 200 || statusCode >= 300) return false;
  final trimmed = body.trim();
  if (trimmed.isEmpty) return false;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map) return false;
    if (decoded.containsKey('version') &&
        !decoded.containsKey('choices') &&
        !decoded.containsKey('results')) {
      return false;
    }
    final usage = decoded['usage'];
    if (usage is Map) {
      final tokens = usage['completion_tokens'];
      if (tokens is num && tokens <= 0) return false;
    }
    if (decoded['error'] != null) return false;
    final choices = decoded['choices'];
    if (choices is List && choices.isNotEmpty) {
      final first = choices.first;
      if (first is Map) {
        final reason = first['finish_reason']?.toString().toLowerCase();
        if (reason == 'error') return false;
      }
    }
    return koboldCompletionText(decoded).trim().isNotEmpty;
  } catch (_) {
    return false;
  }
}

/// Assistant text from an OpenAI or Kobold completion body.
String koboldCompletionText(Map<dynamic, dynamic> decoded) {
  final choices = decoded['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final msg = first['message'];
      if (msg is Map) {
        final c = msg['content'];
        if (c is String) return c;
      }
      final t = first['text'];
      if (t is String) return t;
    }
  }
  final results = decoded['results'];
  if (results is List && results.isNotEmpty) {
    final first = results.first;
    if (first is Map) {
      final t = first['text'];
      if (t is String) return t;
    }
  }
  return '';
}

/// POST `/v1/chat/completions` with [koboldGenerationReadyPayload].
/// Connection-refused / empty / version JSON → false (retry the gate).
Future<bool> probeKoboldGenerationReady({
  required String baseUrl,
  Future<http.Response> Function(Uri uri, String body)? send,
}) async {
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  final uri = Uri.parse('$root/v1/chat/completions');
  final payload = jsonEncode(koboldGenerationReadyPayload());
  try {
    final resp = send != null
        ? await send(uri, payload)
        : await http
              .post(
                uri,
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
                body: payload,
              )
              .timeout(const Duration(seconds: 8));
    return koboldCompletionIsGenerationReady(resp.statusCode, resp.body);
  } catch (_) {
    return false;
  }
}

/// Unload/reload can drop the HTTP socket for a beat (kcpp_instance
/// teardown). Connection-refused is a blip, not "admin is off".
bool koboldAdminErrorIsTransient(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('connection refused') ||
      s.contains('connection reset') ||
      s.contains('connection closed') ||
      s.contains('socketexception') ||
      s.contains('clientexception') ||
      (s.contains('timed out') || s.contains('timeout'));
}

/// Hung `reload_config` — fail closed once, do not retry 8×.
bool koboldAdminErrorIsTimeout(Object error) {
  final s = error.toString().toLowerCase();
  return s.contains('timeout') || s.contains('timed out');
}

/// Admin HTTP must not block forever (live: prepare-worker hung, model inactive).
const kKoboldAdminHttpTimeout = Duration(seconds: 45);

const kKoboldAdminRetryAttempts = 8;
const kKoboldAdminRetryDelay = Duration(milliseconds: 250);
const kKoboldAdminRetryCap = Duration(seconds: 2);

/// Wait after transient fail [retryIndex] (1-based). [base] zero keeps tests
/// instant. Otherwise 250, 500, 1000, 2000… so a blip longer than 1s recovers.
Duration koboldAdminRetryWait(int retryIndex, Duration base) {
  if (base <= Duration.zero) return Duration.zero;
  final shift = (retryIndex - 1).clamp(0, 3);
  var ms = base.inMilliseconds * (1 << shift);
  if (ms > kKoboldAdminRetryCap.inMilliseconds) {
    ms = kKoboldAdminRetryCap.inMilliseconds;
  }
  return Duration(milliseconds: ms);
}

/// One Kobold process: nested mouth/worker admin calls must not overlap.
class KoboldAdminSwapLock {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() work) {
    final done = _tail.then((_) => work());
    _tail = done.then((_) {}, onError: (_) {});
    return done;
  }
}

/// Retry [action] on a transient admin blip. Non-transient misses
/// (`success: false`) throw immediately.
Future<T> koboldAdminRetry<T>(
  Future<T> Function() action, {
  int attempts = kKoboldAdminRetryAttempts,
  Duration delay = kKoboldAdminRetryDelay,
  void Function(Object error, int attempt)? onRetry,
}) async {
  final n = attempts < 1 ? 1 : attempts;
  Object? last;
  for (var i = 0; i < n; i++) {
    try {
      return await action();
    } catch (e) {
      last = e;
      if (koboldAdminErrorIsTimeout(e) ||
          !koboldAdminErrorIsTransient(e) ||
          i == n - 1) {
        rethrow;
      }
      onRetry?.call(e, i + 1);
      final wait = koboldAdminRetryWait(i + 1, delay);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
  }
  throw last!;
}

/// Stage requested files and return the names reload_config should send.
({String filename, String overrideConfig}) koboldAdminStagedReload({
  required String filename,
  required String overrideConfig,
  required String adminDir,
  required String modelPath,
  required String kcppsPath,
}) {
  var file = filename;
  var over = overrideConfig;
  if (file != 'initial_model' && file != 'unload_model') {
    final src = modelPath.trim().isNotEmpty ? modelPath : kcppsPath;
    file = stageKoboldAdminFile(adminDir, src) ?? file;
  }
  if (over.isNotEmpty) {
    over = stageKoboldAdminFile(adminDir, kcppsPath) ?? over;
  }
  return (filename: file, overrideConfig: over);
}

/// Place [filePath] in [adminDir] so reload_config's jail can see it.
/// Returns the admindir-relative name, or null if staging failed.
String? stageKoboldAdminFile(String adminDir, String filePath) {
  final src = filePath.trim();
  if (src.isEmpty) return null;
  final dir = adminDir.trim();
  if (dir.isEmpty) return p.basename(src);
  final name = p.basename(src);
  final dest = p.join(dir, name);
  if (normalizeLocalModelPath(src) == normalizeLocalModelPath(dest)) {
    return name;
  }
  try {
    Directory(dir).createSync(recursive: true);
    final link = Link(dest);
    if (link.existsSync()) {
      try {
        if (normalizeLocalModelPath(link.targetSync()) ==
            normalizeLocalModelPath(src)) {
          return name;
        }
      } catch (_) {}
    } else if (File(dest).existsSync()) {
      return name;
    }
    if (link.existsSync() || File(dest).existsSync()) {
      final unique =
          '${p.basenameWithoutExtension(src)}_'
          '${src.hashCode.abs().toRadixString(16)}${p.extension(src)}';
      final uniqueDest = p.join(dir, unique);
      Link(uniqueDest).createSync(src);
      return unique;
    }
    Link(dest).createSync(src);
    return name;
  } catch (_) {
    return null;
  }
}
