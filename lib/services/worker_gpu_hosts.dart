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

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/kobold_admin_swap.dart';
import 'package:front_porch_ai/services/worker_gpu_swap.dart';

/// Managed KoboldCpp process. Admin HTTP first; process stop/start is the
/// equivalent the app already owns when `--admin` is off.
class KoboldProcessHost implements GpuSwapHost {
  KoboldProcessHost({
    required this.baseUrl,
    required this.stopProcess,
    required this.startProcess,
    this.isProcessRunning,
    this.waitUntilReady,
    this.waitForReload,
    this.waitForUnload,
    this.markNotReady,
    this.markLoading,
    this.requestedModelPath,
    this.requestedKcppsPath,
    this.stageConfig,
    this.isResident,
    this.noteLoadedPair,
    this.noteResident,
    this.onEngineContext,
    this.forgetLoadedPair,
    this.onStep,
    this.purpose,
    this.adminRetryAttempts = kKoboldAdminRetryAttempts,
    this.adminRetryDelay = kKoboldAdminRetryDelay,
    KoboldAdminSwapLock? swapLock,
    HttpGpuSwapHost? admin,
    Future<String?> Function()? engineModel,
    Future<int?> Function()? engineContext,
  }) : _admin = admin,
       _engineModel = engineModel ?? (() => koboldEngineModel(baseUrl)),
       _engineContext = engineContext ?? (() => koboldEngineContext(baseUrl)),
       swapLock = swapLock ?? KoboldAdminSwapLock();

  final String baseUrl;
  final Future<void> Function() stopProcess;

  /// Starts the engine process again, the last resort of [restore]. Throws,
  /// in plain words, when it cannot be started: a restart that was refused
  /// is not waited for.
  final Future<void> Function() startProcess;
  final bool Function()? isProcessRunning;

  /// Waits until the model generates. Used after a process restart, and
  /// after an admin reload when [waitForReload] is not given.
  final Future<void> Function()? waitUntilReady;

  /// Waits for an admin reload that was just asked for to really happen:
  /// the engine starts a new model process, and that one is ready. The
  /// reload call returns before anything has happened, and the old model
  /// goes on answering for a moment.
  final Future<void> Function()? waitForReload;

  /// Waits until the engine reports that nothing is loaded.
  final Future<void> Function()? waitForUnload;

  final void Function()? markNotReady;

  /// Like [markNotReady] for a reload the engine accepted, with the status
  /// line saying what is loading instead of "unloading".
  final void Function(String step)? markLoading;

  /// GGUF this host must have resident after [restore].
  final String? requestedModelPath;

  /// The `.kcpps` this host's role uses, if any.
  final String? requestedKcppsPath;

  /// Writes this role's ready-to-run config into the admin folder and
  /// returns its file name there, plus a key for its content. The reload
  /// is asked for by that name. Null: the engine is asked for the model it
  /// was started with.
  final Future<KoboldStagedRole> Function()? stageConfig;

  /// Whether the config with this key is what the engine has loaded.
  final bool Function(String key)? isResident;

  /// Stamp the pair admin just loaded and re-arm ready (process stays up).
  final FutureOr<void> Function(String modelPath, String kcppsPath)?
  noteLoadedPair;

  /// Record the content key of what admin just loaded.
  final void Function(String key)? noteResident;

  /// The context the engine runs after a reload: chat's prompts are held
  /// to it.
  final void Function(int? context)? onEngineContext;

  /// A reload did not load what it asked for: the pair noted for it is not
  /// what runs.
  final void Function()? forgetLoadedPair;

  /// What the engine says it has loaded, and its context.
  final Future<String?> Function() _engineModel;
  final Future<int?> Function() _engineContext;

  /// Plain words for the status line: which model is loading, and why.
  final void Function(String step)? onStep;

  /// What this role's model is for ("chat", "the story"), for [onStep].
  final String? purpose;

  final int adminRetryAttempts;
  final Duration adminRetryDelay;
  final KoboldAdminSwapLock swapLock;
  final HttpGpuSwapHost? _admin;

  @override
  String get label {
    final model = requestedModelPath?.trim() ?? '';
    if (model.isEmpty) return 'kobold:$baseUrl';
    return 'kobold:$model';
  }

  bool get _processAlive => isProcessRunning?.call() == true;

  /// The process is known not to run, so no admin call can be answered. A
  /// host that cannot tell (no [isProcessRunning]) asks the admin first.
  bool get _knownDown => isProcessRunning != null && !_processAlive;

  Future<void> _runAdmin(Future<void> Function() action, String op) {
    return koboldAdminRetry(
      action,
      attempts: adminRetryAttempts,
      delay: adminRetryDelay,
      onRetry: (e, n) =>
          debugPrint('[GpuSwap] Kobold admin $op blip, retry $n: $e'),
    );
  }

  @override
  Future<void> unload() async {
    await swapLock.enqueue(() async {
      final admin = _admin;
      if (admin != null && !_knownDown) {
        try {
          await _runAdmin(admin.unload, 'unload');
          markNotReady?.call();
          await waitForUnload?.call();
          return;
        } catch (e) {
          if (koboldAdminErrorIsTimeout(e) && _processAlive) {
            debugPrint(
              '[GpuSwap] Kobold admin unload timed out, process still up '
              '— not stopping: $e',
            );
            markNotReady?.call();
            rethrow;
          }
          if (_processAlive && koboldAdminErrorIsTransient(e)) {
            debugPrint(
              '[GpuSwap] Kobold admin unload missed, process still up '
              '— not stopping: $e',
            );
            markNotReady?.call();
            return;
          }
          debugPrint(
            '[GpuSwap] Kobold admin unload failed '
            '(last-resort process stop): $e',
          );
        }
      } else {
        debugPrint(
          '[GpuSwap] Kobold ${admin == null ? 'admin unavailable' : 'not running'}'
          ' — last-resort process stop',
        );
      }
      await stopProcess();
    });
  }

  @override
  Future<void> restore() async {
    await swapLock.enqueue(() async {
      final staged = await stageConfig?.call();
      // Already what the engine has loaded: nothing to send.
      if (staged != null && isResident?.call(staged.key) == true) return;

      final model = (staged?.modelPath ?? requestedModelPath ?? '').trim();
      final why = purpose == null ? '' : ' for $purpose';
      final step = model.isEmpty
          ? 'Loading model$why...'
          : 'Loading ${p.basename(model)}$why...';
      if (model.isNotEmpty) onStep?.call(step);

      var reloaded = false;
      Object? lastError;
      final admin = _admin;
      // A process known not to run cannot answer: it is restarted at once
      // instead of after the admin retries have run out.
      if (admin != null && !_knownDown) {
        try {
          await _runAdmin(
            () => admin.reloadConfig(
              filename: staged?.filename ?? 'initial_model',
            ),
            'restore',
          );
          reloaded = true;
        } catch (e) {
          lastError = e;
          debugPrint(
            '[GpuSwap] Kobold admin restore failed '
            '${_processAlive && koboldAdminErrorIsTransient(e) ? '(process still up — not restarting)' : '(last-resort process restart)'}'
            ': $e',
          );
        }
      } else {
        debugPrint(
          '[GpuSwap] Kobold ${admin == null ? 'admin unavailable' : 'not running'}'
          ' — last-resort process restart',
        );
      }
      if (reloaded) {
        // The engine has only been ASKED. The old model keeps answering for
        // a moment, and must not be mistaken for the new one being ready.
        if (staged != null) {
          final loading = markLoading;
          loading != null ? loading(step) : markNotReady?.call();
        }
        // What the engine was told to load. Whether it has loaded it is
        // the ready flag, set by the wait, and the check after it;
        // listeners on that flag read these paths, so they are written
        // first.
        await _notePair(staged);
        try {
          await (waitForReload ?? waitUntilReady)?.call();
          await _checkLoaded(staged);
          return;
        } on KoboldSwapTimeout catch (e) {
          // It restarted on this config and is still loading it: starting
          // it again would only start the load again.
          if (e.restarted) rethrow;
          // It never acted on the request. Last resort below.
          lastError = e;
          debugPrint('[GpuSwap] Kobold did not act on the reload: $e');
        }
      }
      // A reload the engine never acted on is decided by what it is, not by
      // the words in its message.
      final permanent =
          lastError is KoboldSwapTimeout ||
          (lastError != null && !koboldAdminErrorIsTransient(lastError));
      if (!_processAlive || permanent || admin == null) {
        if (_processAlive) await stopProcess();
        await startProcess();
      } else {
        throw lastError ??
            StateError('Kobold admin restore missed, process still up');
      }
      await waitUntilReady?.call();
      await _noteLoaded(staged);
    });
  }

  Future<void> _noteLoaded(KoboldStagedRole? staged) async {
    await _notePair(staged);
    if (staged != null) noteResident?.call(staged.key);
  }

  Future<void> _notePair(KoboldStagedRole? staged) async {
    final noted = noteLoadedPair?.call(
      staged?.modelPath ?? requestedModelPath ?? '',
      staged?.kcppsPath ?? requestedKcppsPath ?? '',
    );
    if (noted is Future<void>) await noted;
  }

  /// A reload is checked, not assumed: KoboldCpp answers a config it cannot
  /// load by going back to the one it was started with, and says nothing.
  Future<void> _checkLoaded(KoboldStagedRole? staged) async {
    if (staged == null) return;
    final model = await _engineModel();
    final ctx = await _engineContext();
    final wanted = staged.contextSize;
    if (!koboldModelNameMatches(model, staged.expectedModel) ||
        (ctx != null && wanted != null && ctx != wanted)) {
      noteResident?.call(''); // nothing is known to be resident
      forgetLoadedPair?.call();
      onEngineContext?.call(ctx);
      throw KoboldSwapFailed(
        'KoboldCpp could not load ${p.basename(staged.modelPath)}; '
        'it went back to ${model ?? 'its startup model'}.',
      );
    }
    noteResident?.call(staged.key);
    // Chat's prompts are held to the context the engine really runs.
    if (staged.filename == kStagedChatConfig && ctx != null) {
      onEngineContext?.call(ctx);
    }
  }
}
