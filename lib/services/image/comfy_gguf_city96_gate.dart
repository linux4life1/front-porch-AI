// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'comfy_gguf_city96.dart';
import 'comfy_model_paths.dart';
import 'local_model_roots.dart';

/// The published Qwen-Image 2.1 GGUF, e.g. `qwen-image-2.1-Q2_K.gguf`.
bool isQwenImage21GgufUnet(String name) {
  final base = p.basename(name.replaceAll('\\', '/')).toLowerCase();
  if (!base.endsWith('.gguf')) return false;
  if (!base.contains('qwen') || !base.contains('image')) return false;
  return base.contains('2.1') || base.contains('2_1');
}

final RegExp _qwen3Vl = RegExp(r'qwen[-_ ]?3[-_ .]?vl');

/// Its Qwen3-VL text encoder, e.g. `Qwen3-VL-8B-Instruct-Q4_K_M.gguf`. A
/// plain Qwen3 encoder such as `qwen_3_4b.gguf` is not one.
bool isQwen3VlGgufEncoder(String name) {
  final base = p.basename(name.replaceAll('\\', '/')).toLowerCase();
  if (!base.endsWith('.gguf') || base.contains('mmproj')) return false;
  return _qwen3Vl.hasMatch(base);
}

/// True when the graph about to be posted loads a file from the Qwen-Image
/// 2.1 GGUF pair: the unet or its Qwen3-VL encoder. Stock City96 cannot load
/// either half. Saved choices the graph does not use never count.
bool graphNeedsCity96Patch(Map<String, dynamic> graph) {
  for (final node in graph.values) {
    if (node is! Map) continue;
    final inputs = node['inputs'];
    if (inputs is! Map) continue;
    for (final entry in inputs.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is! String) continue;
      if (key == 'unet_name' && isQwenImage21GgufUnet(value)) return true;
      if (key.startsWith('clip_name') && isQwen3VlGgufEncoder(value)) {
        return true;
      }
    }
  }
  return false;
}

/// Stops a generate that needs the GGUF loader update. [message] says so for
/// this model only; every other model generates normally.
class ComfyLoaderUpdateNeeded implements Exception {
  const ComfyLoaderUpdateNeeded(this.message);

  final String message;

  @override
  String toString() => message;
}

/// What the gate found for one posted graph.
enum City96State {
  /// The graph does not use the Qwen-Image 2.1 GGUF pair.
  notNeeded,

  /// The loader at the configured ComfyUI already reads it.
  ready,

  /// The loader was just updated; ComfyUI must restart to load it.
  restartNeeded,

  /// The loader cannot be updated from here; see the message.
  needsUpdate,
}

class City96Check {
  const City96Check(this.state, [this.message]);

  final City96State state;
  final String? message;
}

/// What the person is asked before their loader is changed.
class City96Question {
  const City96Question({required this.loaderPath, required this.comfyUrl});

  final String loaderPath;
  final String comfyUrl;
}

/// Finds `ComfyUI-GGUF/loader.py` for the ComfyUI serving [comfyUrl], or
/// null when that install cannot be found on this computer.
typedef City96Locator = Future<File?> Function(String comfyUrl);

/// Asks once on the desktop. True means update it.
typedef City96Asker = Future<bool> Function(City96Question question);

const String kCity96NeedsUpdate = 'This model needs the GGUF loader update.';

String _needs(String why) => '$kCity96NeedsUpdate $why';

/// The loader of the running ComfyUI on [comfyUrl]'s port, and only that one.
/// No other install on this computer is ever a candidate.
Future<File?> city96LoaderForUrl(
  String comfyUrl, {
  List<ComfyProcessSnapshot>? processes,
}) async {
  final port = comfyUrlPort(comfyUrl);
  final procs = processes ?? await scanComfyProcesses();
  for (final proc in procs) {
    final hints = comfyLaunchHints(
      proc.command,
      cwd: proc.cwd,
      executable: proc.executable,
    );
    if (hints.port != port) continue;
    for (final dir in [hints.mainPyDir, proc.cwd]) {
      if (dir == null || dir.isEmpty) continue;
      final loader = File(
        p.join(dir, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
      );
      if (await loader.exists()) return loader;
    }
    return null;
  }
  return null;
}

/// Updates City96's `loader.py` for Qwen-Image 2.1 GGUF, carefully.
///
/// Only when the posted graph uses that pair, only the ComfyUI at the
/// configured URL, and only after the person says yes (asked once per loader
/// per app run). The original is kept as `loader.py.bak` and the update is
/// written to a temp file and renamed into place.
class City96Gate {
  City96Gate({City96Locator? locate, this.ask})
    : _locate = locate ?? city96LoaderForUrl;

  final City96Locator _locate;

  /// Set by the desktop shell. With no asker the loader is never changed.
  City96Asker? ask;

  final Map<String, bool> _answers = {};

  /// The one the app uses. Tests put their own in place.
  static City96Gate instance = City96Gate();

  /// Where the loader stands, without asking or writing anything.
  Future<(City96Check, File?, City96LoaderPatch?)> _inspect(
    String comfyUrl,
    Map<String, dynamic> graph,
  ) async {
    if (!graphNeedsCity96Patch(graph)) {
      return (const City96Check(City96State.notNeeded), null, null);
    }
    if (!await comfyHostIsLocal(comfyUrl)) {
      return (
        City96Check(
          City96State.needsUpdate,
          _needs(
            'This ComfyUI is on another computer, so Front Porch cannot '
            'update its ComfyUI-GGUF loader. Update ComfyUI-GGUF there.',
          ),
        ),
        null,
        null,
      );
    }
    final loader = await _locate(comfyUrl);
    if (loader == null) {
      return (
        City96Check(
          City96State.needsUpdate,
          _needs(
            'The ComfyUI running at $comfyUrl could not be found on this '
            'computer (for example it runs in Docker), or it has no '
            'ComfyUI-GGUF loader. Update ComfyUI-GGUF there.',
          ),
        ),
        null,
        null,
      );
    }
    final String source;
    try {
      source = await loader.readAsString();
    } on FileSystemException catch (e) {
      debugPrint('City96 loader unreadable: ${e.osError?.errorCode}');
      return (
        City96Check(
          City96State.needsUpdate,
          _needs('Its ComfyUI-GGUF loader could not be read.'),
        ),
        loader,
        null,
      );
    }
    final patch = patchCity96Loader(source);
    if (!patch.recognized) {
      return (
        City96Check(
          City96State.needsUpdate,
          _needs(
            'This ComfyUI-GGUF loader is a version Front Porch does not '
            'recognize, so it was left alone.',
          ),
        ),
        loader,
        patch,
      );
    }
    if (!patch.changed) {
      return (const City96Check(City96State.ready), loader, patch);
    }
    return (
      City96Check(
        City96State.needsUpdate,
        _needs('Its ComfyUI-GGUF loader has not been updated yet.'),
      ),
      loader,
      patch,
    );
  }

  /// Readiness for [graph] without asking or writing. For the desk's Ready
  /// line: only a graph that uses the pair can come back as needing it.
  Future<City96Check> check({
    required String comfyUrl,
    required Map<String, dynamic> graph,
  }) async {
    final (result, _, _) = await _inspect(comfyUrl, graph);
    return result;
  }

  /// Before posting [graph]: asks, updates, or explains. Every state other
  /// than [City96State.notNeeded] and [City96State.ready] stops this post.
  Future<City96Check> ensure({
    required String comfyUrl,
    required Map<String, dynamic> graph,
  }) async {
    final (result, loader, patch) = await _inspect(comfyUrl, graph);
    if (loader == null || patch == null || !patch.changed) return result;
    if (!patch.recognized) return result;
    final asker = ask;
    final known = _answers[loader.path];
    final bool yes;
    if (known != null) {
      yes = known;
    } else if (asker == null) {
      return City96Check(
        City96State.needsUpdate,
        _needs('Open Front Porch on this computer to allow the update.'),
      );
    } else {
      yes = await asker(
        City96Question(loaderPath: loader.path, comfyUrl: comfyUrl),
      );
      _answers[loader.path] = yes;
    }
    if (!yes) {
      return City96Check(
        City96State.needsUpdate,
        _needs('You chose not to update ComfyUI-GGUF.'),
      );
    }
    try {
      await writeCity96Loader(loader, patch.source);
    } on FileSystemException catch (e) {
      debugPrint('City96 loader not written: ${e.osError?.errorCode}');
      return City96Check(
        City96State.needsUpdate,
        _needs('Its ComfyUI-GGUF loader could not be written.'),
      );
    }
    return const City96Check(
      City96State.restartNeeded,
      "ComfyUI-GGUF's loader was updated for Qwen-Image 2.1 (the original is "
      'saved as loader.py.bak). Restart ComfyUI, then generate again.',
    );
  }

  /// Throws [ComfyLoaderUpdateNeeded] when [graph] cannot be posted yet.
  Future<void> ensureOrThrow({
    required String comfyUrl,
    required Map<String, dynamic> graph,
  }) async {
    final result = await ensure(comfyUrl: comfyUrl, graph: graph);
    switch (result.state) {
      case City96State.notNeeded:
      case City96State.ready:
        return;
      case City96State.restartNeeded:
      case City96State.needsUpdate:
        throw ComfyLoaderUpdateNeeded(result.message ?? kCity96NeedsUpdate);
    }
  }
}

/// Keeps the original as `loader.py.bak`, then replaces `loader.py` through a
/// temp file beside it, so a crash never leaves half a loader.
Future<void> writeCity96Loader(File loader, String patched) async {
  await loader.copy('${loader.path}.bak');
  final temp = File('${loader.path}.fpai-tmp');
  try {
    final out = await temp.open(mode: FileMode.write);
    try {
      await out.writeString(patched);
      await out.flush();
    } finally {
      await out.close();
    }
    await temp.rename(loader.path);
  } catch (_) {
    if (await temp.exists()) await temp.delete();
    rethrow;
  }
}
