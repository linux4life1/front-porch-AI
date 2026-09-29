// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'comfy_gguf_city96.dart';
import 'comfy_gguf_city96_write.dart';
import 'comfy_model_paths.dart';
import 'comfy_process_probe.dart';
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
  const City96Check(this.state, [this.message, this.canUpdate = false]);

  final City96State state;
  final String? message;

  /// The loader is where it should be, and the person could allow the
  /// update from here. False when it cannot be changed at all.
  final bool canUpdate;
}

/// Set (as a zone value) around a call that comes from the phone or the web.
/// That caller cannot answer a dialog on this computer, so the gate answers it
/// right away instead of leaving the request waiting.
const Symbol kCity96NoAsk = #fpaiCity96NoAsk;

const String kCity96ConfirmOnDesktop =
    'Confirm the update in Front Porch on the computer that runs ComfyUI, '
    'then generate again.';

/// What the person is asked before their loader is changed.
class City96Question {
  const City96Question({required this.loaderPath, required this.comfyUrl});

  final String loaderPath;
  final String comfyUrl;
}

/// Finds `ComfyUI-GGUF/loader.py` for the ComfyUI serving [comfyUrl], or
/// null when that install cannot be found on this computer.
typedef City96Locator = Future<File?> Function(String comfyUrl);

/// Asks once on the desktop. True means update it, false means the person said
/// no. Null means nobody could be asked (the window is gone); that is not an
/// answer and is never remembered.
typedef City96Asker = Future<bool?> Function(City96Question question);

const String kCity96NeedsUpdate = 'This model needs the GGUF loader update.';

const String _kRestart =
    "ComfyUI-GGUF's loader was updated for Qwen-Image 2.1, but the ComfyUI "
    'that is running has not loaded it. Restart ComfyUI, then generate again.';

const String _kRestartAfterWrite =
    "ComfyUI-GGUF's loader was updated for Qwen-Image 2.1 (the original is "
    'saved as loader.py.bak). Restart ComfyUI, then generate again.';

String _needs(String why) => '$kCity96NeedsUpdate $why';

/// The running ComfyUI on [comfyUrl]'s port and its loader, and only that one:
/// its command line names that port, this user owns it, and it is really the
/// process listening there. Another user's process, or a look-alike that is
/// not listening, is never a candidate.
Future<({File loader, int? pid})?> city96TargetForUrl(
  String comfyUrl, {
  List<ComfyProcessSnapshot>? processes,
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async {
  final port = comfyUrlPort(comfyUrl);
  final procs = processes ?? await scanComfyProcesses();
  final me = await probe.currentUid();
  Set<int>? listeners;
  var asked = false;
  for (final proc in procs) {
    final hints = comfyLaunchHints(
      proc.command,
      cwd: proc.cwd,
      executable: proc.executable,
    );
    if (hints.port != port) continue;
    if (me != null && proc.uid != null && proc.uid != me) continue;
    if (!asked) {
      listeners = await probe.listeningPids(port);
      asked = true;
    }
    if (listeners != null &&
        (proc.pid == null || !listeners.contains(proc.pid))) {
      continue;
    }
    for (final dir in [hints.mainPyDir, proc.cwd]) {
      if (dir == null || dir.isEmpty) continue;
      final loader = File(
        p.join(dir, 'custom_nodes', 'ComfyUI-GGUF', 'loader.py'),
      );
      if (await loader.exists()) return (loader: loader, pid: proc.pid);
    }
  }
  return null;
}

Future<File?> city96LoaderForUrl(
  String comfyUrl, {
  List<ComfyProcessSnapshot>? processes,
  ComfyProcessProbe probe = const ComfyProcessProbe(),
}) async => (await city96TargetForUrl(
  comfyUrl,
  processes: processes,
  probe: probe,
))?.loader;

/// The id of the process serving [comfyUrl], for noticing a restart.
Future<int?> city96PidForUrl(String comfyUrl) async =>
    (await city96TargetForUrl(comfyUrl))?.pid;

/// Updates City96's `loader.py` for Qwen-Image 2.1 GGUF, carefully.
///
/// Only when the posted graph uses that pair, only the ComfyUI at the
/// configured URL, and only after the person says yes (asked once per loader
/// per app run). The original is kept as `loader.py.bak` and the update is
/// written to a temp file and renamed into place.
class City96Gate {
  City96Gate({
    City96Locator? locate,
    this.ask,
    this.probe = const ComfyProcessProbe(),
    Future<int?> Function(String comfyUrl)? pidFor,
    Future<void> Function(File loader, String patched)? write,
  }) : _locate = locate ?? city96LoaderForUrl,
       _pidFor = pidFor ?? city96PidForUrl,
       _write = write;

  final City96Locator _locate;
  final Future<void> Function(File loader, String patched)? _write;
  final Future<int?> Function(String comfyUrl) _pidFor;
  final ComfyProcessProbe probe;

  /// Set by the desktop shell. With no asker the loader is never changed.
  City96Asker? ask;

  final Map<String, bool> _answers = {};

  /// Loaders written during this run, with the id of the ComfyUI process that
  /// was running then. ComfyUI reads the loader when it starts, so the update
  /// counts only once a different process serves that URL.
  final Map<String, int?> _updated = {};

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
      if (_updated.containsKey(loader.path)) {
        final then = _updated[loader.path];
        final now = await _pidFor(comfyUrl);
        if (then == null || now == null || now == then) {
          return (
            const City96Check(City96State.restartNeeded, _kRestart),
            loader,
            patch,
          );
        }
        _updated.remove(loader.path);
      }
      return (const City96Check(City96State.ready), loader, patch);
    }
    final problem = await city96TargetProblem(loader, probe: probe);
    if (problem != null) {
      return (
        City96Check(City96State.needsUpdate, _needs(problem)),
        loader,
        patch,
      );
    }
    return (
      City96Check(
        City96State.needsUpdate,
        _needs('Its ComfyUI-GGUF loader has not been updated yet.'),
        true,
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
  ///
  /// A "no" is remembered for the run, so posting again does not ask again.
  /// [askAgain] is for the person pressing "Update loader…": they are asking
  /// for the question, so an earlier "no" does not answer it.
  Future<City96Check> ensure({
    required String comfyUrl,
    required Map<String, dynamic> graph,
    bool askAgain = false,
  }) async {
    final (result, loader, patch) = await _inspect(comfyUrl, graph);
    if (loader == null || patch == null || !patch.changed) return result;
    if (!patch.recognized || !result.canUpdate) return result;
    final asker = ask;
    final known = askAgain ? null : _answers[loader.path];
    final bool yes;
    if (known != null) {
      yes = known;
    } else if (Zone.current[kCity96NoAsk] == true) {
      return City96Check(
        City96State.needsUpdate,
        _needs(kCity96ConfirmOnDesktop),
        true,
      );
    } else if (asker == null) {
      return City96Check(
        City96State.needsUpdate,
        _needs('Open Front Porch on this computer to allow the update.'),
        true,
      );
    } else {
      final answer = await asker(
        City96Question(loaderPath: loader.path, comfyUrl: comfyUrl),
      );
      if (answer == null) {
        return City96Check(
          City96State.needsUpdate,
          _needs('Open Front Porch on this computer to allow the update.'),
          true,
        );
      }
      yes = answer;
      _answers[loader.path] = yes;
    }
    if (!yes) {
      return City96Check(
        City96State.needsUpdate,
        _needs('You chose not to update ComfyUI-GGUF.'),
        true,
      );
    }
    final pid = await _pidFor(comfyUrl);
    try {
      await (_write ?? (l, text) => writeCity96Loader(l, text, probe: probe))(
        loader,
        patch.source,
      );
    } on City96WriteRefused catch (e) {
      return City96Check(City96State.needsUpdate, _needs(e.message));
    } on FileSystemException catch (e) {
      debugPrint('City96 loader not written: ${e.osError?.errorCode}');
      return City96Check(
        City96State.needsUpdate,
        _needs('Its ComfyUI-GGUF loader could not be written.'),
        true,
      );
    }
    _updated[loader.path] = pid;
    return const City96Check(City96State.restartNeeded, _kRestartAfterWrite);
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
