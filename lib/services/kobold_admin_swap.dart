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

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kobold/kcpps_codec.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// App-owned `--admindir` so reload_config can see GGUF + `.kcpps` names.
String koboldAdminDirFor(StorageService storage) {
  final root = storage.rootPath?.trim() ?? '';
  if (root.isNotEmpty) return p.join(root, 'kobold_admin');
  return p.join(storage.modelsDir.path, 'kobold_admin');
}

/// KoboldCpp `POST /api/admin/reload_config` body.
///
/// The app names a config it staged in `--admindir` (`fpai-<role>.kcpps`),
/// or `unload_model` / `initial_model`. The engine replaces its model
/// process with one started from that file; the parent process, its port
/// and its admin folder stay.
Map<String, String> koboldAdminReloadBody({required String filename}) => {
  'filename': filename,
};

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
  int _queued = 0;

  /// A swap is waiting or running.
  bool get busy => _queued > 0;

  Future<T> enqueue<T>(Future<T> Function() work) {
    _queued++;
    final done = _tail.then((_) => work());
    _tail = done.then((_) {}, onError: (_) {}).whenComplete(() => _queued--);
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

/// Seconds the engine's model process has been running, or null when
/// nothing answers. It starts again from zero on every reload and unload,
/// which is how a swap is known to have really happened.
Future<double?> koboldEngineUptime(String baseUrl) async {
  final body = await _engineJson(baseUrl, 'api/extra/perf');
  final uptime = body?['uptime'];
  return uptime is num ? uptime.toDouble() : null;
}

/// What the engine says it has loaded: a model name, `inactive` when
/// nothing is, or null when nothing answers.
Future<String?> koboldEngineModel(String baseUrl) async =>
    (await _engineJson(baseUrl, 'api/v1/model'))?['result']?.toString();

/// The context the loaded model really has, or null when nothing answers.
Future<int?> koboldEngineContext(String baseUrl) async {
  final v = (await _engineJson(
    baseUrl,
    'api/extra/true_max_context_length',
  ))?['value'];
  return v is num ? v.toInt() : null;
}

/// KoboldCpp's model name for [config]: hordemodelname, else the
/// model file's stem with re.sub(r'[^\w\d\.\-_]', '', s) applied.
String koboldExpectedModelName(Map<String, dynamic> config) {
  final horde = config['hordemodelname']?.toString().trim() ?? '';
  final name = horde.isNotEmpty
      ? horde
      : p.basenameWithoutExtension(kcppsModelOf(config));
  return name.replaceAll(RegExp(r'[^\w\d\.\-_]'), '');
}

/// The context KoboldCpp runs for [config]: its contextsize. Null when it
/// sets none, as KoboldCpp's default differs by version.
int? koboldExpectedContext(Map<String, dynamic> config) {
  final v = config['contextsize'];
  return v is num ? v.toInt() : int.tryParse('${v ?? ''}');
}

bool koboldModelNameMatches(String? engine, String expected) {
  String n(String s) => s
      .replaceFirst(RegExp(r'^koboldcpp/'), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  return engine != null && n(engine) == n(expected);
}

Future<Map<dynamic, dynamic>?> _engineJson(String baseUrl, String path) async {
  final root = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  try {
    final resp = await http
        .get(Uri.parse('$root/$path'))
        .timeout(const Duration(seconds: 3));
    if (resp.statusCode != 200) return null;
    final decoded = jsonDecode(resp.body);
    return decoded is Map ? decoded : null;
  } catch (_) {
    // Not answering is an answer here: the engine is down or restarting.
    return null;
  }
}
