// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Shared by the `kobold_live` suites: where the real KoboldCpp and a small
// model are, and plain HTTP questions to a running engine.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The KoboldCpp executable to test against.
final String liveEngineBin = Platform.environment['KOBOLD_LIVE_BIN'] ?? '';

/// A small `.gguf` the engine can load in a few seconds.
final String liveEngineModel = Platform.environment['KOBOLD_LIVE_MODEL'] ?? '';

/// Why the live suites are skipped here, or null when they can run.
String? get liveEngineSkip {
  if (liveEngineBin.isEmpty || liveEngineModel.isEmpty) {
    return 'set KOBOLD_LIVE_BIN and KOBOLD_LIVE_MODEL to run against a real '
        'KoboldCpp';
  }
  if (!File(liveEngineBin).existsSync()) return 'no engine at $liveEngineBin';
  if (!File(liveEngineModel).existsSync()) {
    return 'no model at $liveEngineModel';
  }
  return null;
}

/// A copy of the engine inside [folder], so "the app's engine folder" in a
/// test is never the one a real install uses.
Future<String> copyEngineInto(Directory folder) async {
  await folder.create(recursive: true);
  final copy = p.join(folder.path, p.basename(liveEngineBin));
  await File(liveEngineBin).copy(copy);
  if (!Platform.isWindows) await Process.run('chmod', ['+x', copy]);
  return copy;
}

Future<int> freePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

Future<Object?> _get(int port, String path) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(
      Uri.parse('http://127.0.0.1:$port$path'),
    );
    final response = await request.close().timeout(const Duration(seconds: 5));
    return jsonDecode(await utf8.decodeStream(response));
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// What the engine on [port] says is loaded: a model name, `inactive` after
/// an unload, or null when nothing answers.
Future<String?> liveLoadedModel(int port) async {
  final body = await _get(port, '/api/v1/model');
  return body is Map ? body['result']?.toString() : null;
}

/// The context size the loaded model really has.
Future<int?> liveContextSize(int port) async {
  final body = await _get(port, '/api/extra/true_max_context_length');
  final value = body is Map ? body['value'] : null;
  return value is num ? value.toInt() : null;
}

/// Waits until the engine on [port] reports a loaded model.
Future<void> waitForLiveModel(
  int port, {
  Duration timeout = const Duration(minutes: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final loaded = await liveLoadedModel(port);
    if (loaded != null && loaded != 'inactive') return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw StateError('the engine on port $port never reported a model');
}

/// Waits until the engine on [port] reports that nothing is loaded.
Future<void> waitForLiveUnload(
  int port, {
  Duration timeout = const Duration(minutes: 1),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (await liveLoadedModel(port) == 'inactive') return;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  throw StateError('the engine on port $port never finished unloading');
}

/// Process ids whose command line begins with [text] literally: what was
/// started from that folder or executable.
Future<Set<int>> livePidsStartedFrom(String text) async {
  final out = await Process.run('pgrep', ['-f', '^${RegExp.escape(text)}']);
  return (out.stdout as String)
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map(int.parse)
      .toSet();
}
