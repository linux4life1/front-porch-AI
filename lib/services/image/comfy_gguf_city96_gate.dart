// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'image.dart';
import 'comfy_gguf_city96_write.dart';
import 'comfy_process_probe.dart';
import 'local_model_roots.dart' show comfyHostIsLocal;

export 'city96_records.dart';
export 'comfy_gguf_city96_target.dart'
    show City96Target, city96LoaderForUrl, city96PidForUrl, city96TargetForUrl;

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
  const City96Check(
    this.state, [
    this.message,
    this.canUpdate = false,
    this.othersCanWrite = false,
  ]);

  final City96State state;
  final String? message;

  /// The loader is where it should be, and the person could allow the
  /// update from here. False when it cannot be changed at all.
  final bool canUpdate;

  /// Other users on this computer can change the folder. The person is told
  /// when they are asked.
  final bool othersCanWrite;
}

/// Set (as a zone value) around a call that comes from the phone or the web.
/// That caller cannot answer a dialog on this computer, so the gate answers it
/// right away instead of leaving the request waiting.
const Symbol kCity96NoAsk = #fpaiCity96NoAsk;

/// Runs [body] (and everything it starts) as a phone or web caller: a
/// ComfyUI-GGUF loader update is answered with "confirm on the desktop" at
/// once, and no dialog is raised on this computer for a job nobody there is
/// waiting on.
T withoutCity96Ask<T>(T Function() body) =>
    runZoned(body, zoneValues: {kCity96NoAsk: true});

const String kCity96ConfirmOnDesktop =
    'Confirm the update in Front Porch on the computer that runs ComfyUI, '
    'then generate again.';

/// What the person is asked before their loader is changed.
class City96Question {
  const City96Question({
    required this.loaderPath,
    required this.comfyUrl,
    this.othersCanWrite = false,
  });

  final String loaderPath;
  final String comfyUrl;

  /// Other users on this computer can change the folder: the question says so.
  final bool othersCanWrite;
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
  }) : _locate = locate == null
           ? ((url) => city96TargetForUrl(url, probe: probe))
           : ((url) async =>
                 (loader: await locate(url), pid: null, refused: null)),
       _pidFor =
           pidFor ??
           ((url) async => (await city96TargetForUrl(url, probe: probe)).pid),
       _write = write;

  final Future<City96Target> Function(String comfyUrl) _locate;
  final Future<void> Function(File loader, String patched)? _write;
  final Future<int?> Function(String comfyUrl) _pidFor;
  final ComfyProcessProbe probe;

  /// Set by the desktop shell. With no asker the loader is never changed.
  City96Asker? ask;

  final Map<String, bool> _answers = {};
  final Set<String> _existingSupport = {};

  /// Explicit acknowledgement for this server until Front Porch restarts.
  /// This never writes a loader or claims its runtime support was detected.
  void setExistingSupport(String comfyUrl, {required bool confirmed}) {
    if (confirmed) {
      _existingSupport.add(comfyUrl);
    } else {
      _existingSupport.remove(comfyUrl);
    }
  }

  bool hasExistingSupport(String comfyUrl) =>
      _existingSupport.contains(comfyUrl);

  /// What was written to each loader, and when. ComfyUI reads the loader when
  /// it starts, so an update counts once a ComfyUI that started after the write
  /// is serving the URL. The desktop shell swaps in the saved kind.
  City96Records records = MemoryCity96Records();

  /// The one the app uses. Tests put their own in place.
  static City96Gate instance = City96Gate();

  /// How much later than the write ComfyUI must have started to have read it.
  /// Process start times are whole seconds, and clocks are not exact.
  static const Duration kStartMargin = Duration(seconds: 2);

  /// True until the ComfyUI serving [comfyUrl] is known to have started after
  /// its (already patched) loader was written, with a margin. That is judged
  /// from what Front Porch recorded when it wrote the file, when the file still
  /// has what it wrote (so a clock that is off, a network share or a `touch`
  /// cannot move it); otherwise from the file's own time, which a ComfyUI can
  /// never start after when it is in the future. A start time that cannot be
  /// read is never taken as "loaded".
  Future<bool> _notLoadedYet(
    String comfyUrl,
    File loader,
    String source,
  ) async {
    final record = await records.get(loader.path);
    final DateTime wrote;
    if (record != null && record.hash == city96Hash(source)) {
      wrote = record.at;
    } else {
      wrote = await loader.lastModified();
    }
    final pid = await _pidFor(comfyUrl);
    final started = pid == null ? null : await probe.processStart(pid);
    if (started == null) return true;
    // The record stays once ComfyUI has loaded it: it is replaced by the next
    // write, never dropped, or a later `touch` or a clock that is off would
    // send the file back to being judged by its own time.
    return !started.isAfter(wrote.add(kStartMargin));
  }

  /// Where the loader stands, without asking or writing anything.
  Future<(City96Check, File?, City96LoaderPatch?)> _inspect(
    String comfyUrl,
    Map<String, dynamic> graph,
  ) async {
    if (!graphNeedsCity96Patch(graph)) {
      return (const City96Check(City96State.notNeeded), null, null);
    }
    if (hasExistingSupport(comfyUrl)) {
      return (const City96Check(City96State.ready), null, null);
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
    final target = await _locate(comfyUrl);
    final loader = target.loader;
    if (loader == null) {
      return (
        City96Check(
          City96State.needsUpdate,
          _needs(
            target.refused ??
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
      if (await _notLoadedYet(comfyUrl, loader, source)) {
        return (
          const City96Check(City96State.restartNeeded, _kRestart),
          loader,
          patch,
        );
      }
      return (const City96Check(City96State.ready), loader, patch);
    }
    final judged = await city96Judge(loader, probe: probe);
    if (judged.refusal != null) {
      return (
        City96Check(City96State.needsUpdate, _needs(judged.refusal!)),
        loader,
        patch,
      );
    }
    return (
      City96Check(
        City96State.needsUpdate,
        _needs('Its ComfyUI-GGUF loader has not been updated yet.'),
        true,
        judged.othersCanWrite,
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
        City96Question(
          loaderPath: loader.path,
          comfyUrl: comfyUrl,
          othersCanWrite: result.othersCanWrite,
        ),
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
    await records.put(
      loader.path,
      City96Record(hash: city96Hash(patch.source), at: DateTime.now()),
    );
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
