// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Persistent worker pool for Kokoro TTS.
// Keeps up to 8 long-lived Python processes with the model loaded in RAM.
// Designed to be resilient to individual worker crashes during long narration.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/services/kokoro_chunk.dart';
import 'package:front_porch_ai/services/kokoro_debug.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/wav_utils.dart';

/// Result of a single generation request sent to a worker.
class _GenerationResult {
  final File? file;
  final String? error;
  _GenerationResult({this.file, this.error});
}

/// A single piece of work to be processed by a worker.
class _WorkerJob {
  final KokoroChunk chunk;
  final Completer<_GenerationResult> completer;
  final int requestId;

  _WorkerJob(this.chunk, this.completer, this.requestId);
}

/// Internal handle for one resident kokoro_tts worker process.
///
/// This is now a proper queued actor ("train platform").
/// All work is enqueued and processed serially by a dedicated loop.
/// This guarantees safe, ordered writes to the worker's stdin.
class _KokoroWorker {
  final Process process;
  final StreamSubscription<String> stdoutSub;

  final Queue<_WorkerJob> queue = Queue<_WorkerJob>();
  bool isProcessing = false;
  bool isDead = false;
  int consecutiveErrors = 0;

  // Wakes up the processing loop when new work is enqueued
  Completer<void>? _workSignal;

  // Currently active job (for matching stdout responses)
  _WorkerJob? _currentJob;

  _KokoroWorker(this.process, this.stdoutSub) {
    // Start the dedicated serial processing loop
    _runProcessingLoop();
  }

  /// Enqueue work. The processing loop will handle it one at a time.
  void enqueue(KokoroChunk chunk, Completer<_GenerationResult> completer) {
    final requestId = DateTime.now().microsecondsSinceEpoch;
    final job = _WorkerJob(chunk, completer, requestId);
    queue.add(job);

    kDebugPrint('[Worker] Enqueued chunk #${chunk.originalIndex} (requestId=$requestId). Queue length: ${queue.length}');

    // Wake the loop if it's waiting
    if (_workSignal != null && !_workSignal!.isCompleted) {
      _workSignal!.complete();
    }
  }

  Future<void> _runProcessingLoop() async {
    while (!isDead) {
      if (queue.isEmpty) {
        _workSignal = Completer<void>();
        await _workSignal!.future;
        _workSignal = null;
      }

      if (queue.isEmpty || isDead) continue;

      final job = queue.removeFirst();
      isProcessing = true;
      _currentJob = job;

      kDebugPrint('[Worker] Dequeued and sending chunk #${job.chunk.originalIndex} (requestId=${job.requestId})');

      try {
        final request = {
          'id': job.requestId,
          'text': job.chunk.text,
          'voice': job.chunk.voice,
          'speed': job.chunk.speed,
          'lang': job.chunk.lang,
          'output': job.chunk.outputPath,
          'model': job.chunk.modelPath,
          'voices': job.chunk.voicesPath,
        };

        // === SERIALIZED WRITE — only one at a time per worker ===
        process.stdin.writeln(jsonEncode(request));
        await process.stdin.flush();

        kDebugPrint('[Worker] Sent chunk #${job.chunk.originalIndex} to Python (waiting for response)');

        // Wait here for the response to arrive and complete this job.
        // This ensures we only have one in-flight request per worker at a time,
        // so _currentJob matching in the stdout handler is unambiguous.
        await job.completer.future;

        kDebugPrint('[Worker] Chunk #${job.chunk.originalIndex} completed');

        // At this point completeCurrentJob has already run and cleaned up the state.
        // The loop will now pick up the next job in the queue (if any).

      } catch (e) {
        kDebugPrint('[Worker] Write error for chunk #${job.chunk.originalIndex}: $e');
        consecutiveErrors++;
        _currentJob = null;
        isProcessing = false;
        if (!job.completer.isCompleted) {
          job.completer.complete(_GenerationResult(error: e.toString()));
        }
      }
    }
  }

  /// Called from the pool's stdout handler when a response arrives for this worker.
  void completeCurrentJob(_GenerationResult result) {
    final job = _currentJob;
    if (job != null) {
      kDebugPrint('[Worker] Completing job for chunk #${job.chunk.originalIndex}');
      job.completer.complete(result);
      _currentJob = null;
      isProcessing = false;
    }
  }

  void kill() {
    isDead = true;

    // Wake the loop so it can exit
    if (_workSignal != null && !_workSignal!.isCompleted) {
      _workSignal!.complete();
    }

    stdoutSub.cancel();
    process.kill();

    // Fail any queued work
    for (final job in queue) {
      job.completer.complete(_GenerationResult(error: 'worker died'));
    }
    queue.clear();

    if (_currentJob != null) {
      _currentJob!.completer.complete(_GenerationResult(error: 'worker died'));
      _currentJob = null;
    }
  }
}

/// Manages a small pool of persistent Kokoro worker processes.
/// Each worker loads the ~300MB model once and then serves many requests.
class KokoroWorkerPool {
  final StorageService _storage;

  /// Function provided by KokoroEngine that knows how to spawn the right
  /// bundled binary or python + script for the current platform.
  final Future<Process> Function() _spawnWorker;

  final List<_KokoroWorker> _workers = [];
  final Map<int, Completer<_GenerationResult>> _pending = {};
  bool _isShuttingDown = false;
  int _spawningCount = 0; // prevents overspawning during mass death events

  // Used to limit noisy "Started new worker" debug spam during initial ramp-up
  static int _startupLogCount = 0;

  KokoroWorkerPool(this._storage, this._spawnWorker);

  /// Current desired max workers (comes from the user slider, now capped at 8).
  int get _maxWorkers => _storage.ttsConcurrency.clamp(1, 8);

  /// Main entry point. Takes raw text, chunks it safely, and submits to the pool.
  Future<File?> generateAudio({
    required String text,
    required String voice,
    required double speed,
    required String lang,
    required String outputPath,
    required String modelPath,
    required String voicesPath,
    void Function(double progress)? onProgress,
  }) async {
    if (_isShuttingDown) return null;

    kDebugPrint('[KokoroPool] generateAudio called with text len=${text.length}');

    final bool readEverythingMode = !_storage.ttsIgnoreAsterisks && !_storage.ttsNarrateQuotedOnly;

    final List<KokoroChunk> chunks;

    if (readEverythingMode) {
      // Verbatim mode: use simple hard 100-character chunks (as requested)
      chunks = KokoroChunker.splitFixedCharacterCount(
        text: text,
        voice: voice,
        speed: speed,
        lang: lang,
        modelPath: modelPath,
        voicesPath: voicesPath,
        chunkSize: 100,
      );
    } else {
      // Filtered mode: use the smarter sentence-based chunker
      chunks = KokoroChunker.split(
        text: text,
        voice: voice,
        speed: speed,
        lang: lang,
        modelPath: modelPath,
        voicesPath: voicesPath,
        maxChars: 450,
      );
    }

    if (chunks.isEmpty) return null;

    kDebugPrint('[KokoroPool] Submitting ${chunks.length} chunks for this generateAudio call');

    // Parallel submission across the worker pool.
    // Each _submitSingleChunk waits for a free worker + enqueues; excess work queues naturally.
    // We key results by originalIndex so the final collation is guaranteed in correct order.
    final resultsByIndex = <int, File>{};

    final futures = <Future>[];
    for (final chunk in chunks) {
      futures.add(() async {
        kDebugPrint('[KokoroPool] Submitting chunk #${chunk.originalIndex} (len=${chunk.text.length}) to worker pool');
        final result = await _submitSingleChunk(chunk, modelPath, voicesPath);
        if (result != null) {
          resultsByIndex[chunk.originalIndex] = result;
          if (onProgress != null) {
            final progress = (resultsByIndex.length / chunks.length).clamp(0.0, 0.99);
            onProgress(progress);
          }
        } else {
          kDebugPrint('[KokoroPool] Chunk #${chunk.originalIndex} ultimately failed after retries (will be missing from final audio)');
        }
      }());
    }

    await Future.wait(futures);

    // Final progress update — collation is about to happen
    onProgress?.call(1.0);

    if (resultsByIndex.isEmpty) {
      kDebugPrint('[KokoroPool] All chunks failed for this generateAudio call');
      return null;
    }

    // Sort by original index to guarantee perfect reading order, then collate into one file
    final sortedEntries = resultsByIndex.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final orderedResults = sortedEntries.map((e) => e.value).toList();

    kDebugPrint('[KokoroPool] All sub-chunks complete. Collating ${orderedResults.length} pieces into one file for verbatim playback');

    if (orderedResults.length == 1) return orderedResults.first;

    final combined = await WavUtils.concatenateWavFiles(orderedResults);
    _cleanupFiles(orderedResults);
    return combined;
  }

  void _cleanupFiles(List<File> files) {
    for (final file in files) {
      try { file.deleteSync(); } catch (_) {}
    }
  }

  /// Submits one chunk to a worker with retry logic.
  Future<File?> _submitSingleChunk(
    KokoroChunk chunk,
    String modelPath,
    String voicesPath,
  ) async {
    const maxAttempts = 5;

    for (int attempt = 1; attempt <= maxAttempts; attempt++) {
      kDebugPrint('[KokoroPool] Attempt $attempt for chunk #${chunk.originalIndex}');

      _KokoroWorker? worker;

      // Try to get a worker. If none is ready, wait a bit and retry instead of failing the chunk.
      for (int waitAttempt = 0; waitAttempt < 12; waitAttempt++) { // up to ~2.4 seconds of waiting
        worker = await _getOrCreateFreeWorker();
        if (worker != null) break;

        kDebugPrint('[KokoroPool] No worker ready for chunk #${chunk.originalIndex}, waiting... (wait $waitAttempt)');
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (worker == null) {
        kDebugPrint('[KokoroPool] Still no worker after waiting for chunk #${chunk.originalIndex}. Giving up on this attempt.');
        if (attempt == maxAttempts) return null;
        await Future.delayed(const Duration(milliseconds: 300));
        continue;
      }

      kDebugPrint('[KokoroPool] Enqueuing chunk #${chunk.originalIndex} to a worker (attempt $attempt)');
      final completer = Completer<_GenerationResult>();
      worker.enqueue(chunk, completer);

      final result = await completer.future;

      if (result.error != null) {
        kDebugPrint('[KokoroPool] Chunk #${chunk.originalIndex} failed (attempt $attempt): ${result.error}');
        _handleWorkerDeath(worker);
        if (attempt == maxAttempts) return null;
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }

      final outFile = File(chunk.outputPath);
      return outFile.existsSync() ? outFile : null;
    }

    return null;
  }

  /// Find a non-busy worker, or start a new one if we haven't reached the cap.
  Future<_KokoroWorker?> _getOrCreateFreeWorker() async {
    // Prefer a live worker that is not currently processing
    for (final w in _workers) {
      if (!w.isDead && !w.isProcessing) return w;
    }

    // No available worker — start a new one if we can
    if (_workers.length < _maxWorkers) {
      return await _startNewWorker();
    }

    // At cap — fall back to any non-dead worker (its queue will handle serialization)
    for (final w in _workers) {
      if (!w.isDead) return w;
    }

    return null;
  }

  Future<_KokoroWorker?> _startNewWorker() async {
    if (_workers.length + _spawningCount >= _maxWorkers) {
      return null;
    }

    _spawningCount++;

    Process process;
    try {
      process = await _spawnWorker();
    } catch (e) {
      kDebugPrint('[KokoroPool] Failed to spawn worker: $e');
      _spawningCount--;
      return null;
    }

    // Listen for JSON lines on stdout
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
      _handleWorkerStdout(line);
    });

    // Watch for unexpected death
    unawaited(process.exitCode.then((code) {
      if (!_isShuttingDown) {
        kDebugPrint('[KokoroPool] Worker exited unexpectedly (code $code)');
        _handleWorkerDeathByProcess(process);
      }
    }));

    // Also drain stderr so the process doesn't block
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen((data) {
      if (data.trim().isNotEmpty) {
        kDebugPrint('[KokoroWorker stderr] $data');
      }
    });

    final worker = _KokoroWorker(process, stdoutSub);
    _workers.add(worker);
    _spawningCount--;

    // Only spam the first few "Started new worker" messages to reduce log noise
    if (_startupLogCount < 4) {
      kDebugPrint('[KokoroPool] Started new worker (total: ${_workers.length})');
      _debugPrintWorkerStats();
      _startupLogCount++;
    }
    return worker;
  }

  void _handleWorkerStdout(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;

    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final id = json['id'] as int?;
      if (id == null) return;

      kDebugPrint('[Pool] Received response for requestId=$id');

      // Find which worker this response belongs to and complete its current job
      for (final worker in _workers) {
        if (worker._currentJob?.requestId == id) {
          final isOk = json.containsKey('ok') && json['ok'] == true;
          kDebugPrint('[Pool] Response for chunk #${worker._currentJob!.chunk.originalIndex} → ok=$isOk');

          final result = isOk
              ? _GenerationResult(file: File(worker._currentJob!.chunk.outputPath))
              : _GenerationResult(error: json['error'] as String?);

          worker.completeCurrentJob(result);
          return;
        }
      }

      // Fallback for any old-style pending requests (during transition)
      if (_pending.containsKey(id)) {
        final completer = _pending.remove(id)!;
        if (json.containsKey('ok') && json['ok'] == true) {
          completer.complete(_GenerationResult(file: File('')));
        } else if (json.containsKey('error')) {
          completer.complete(_GenerationResult(error: json['error'] as String?));
        }
      }
    } catch (e) {
      kDebugPrint('[KokoroPool] Bad JSON from worker: $trimmed  ($e)');
    }
  }

  void _handleWorkerDeath(_KokoroWorker worker) {
    _workers.remove(worker);

    kDebugPrint('[KokoroPool] Worker died. Had ${worker.queue.length} jobs in queue + current job: ${worker._currentJob != null}');

    // Kill the process and drain its queue (fail any pending work on this worker)
    worker.kill();

    // Fail any remaining jobs that were enqueued to this worker
    for (final job in worker.queue) {
      job.completer.complete(_GenerationResult(error: 'worker died'));
    }
    worker.queue.clear();

    if (worker._currentJob != null) {
      worker._currentJob!.completer.complete(_GenerationResult(error: 'worker died'));
      worker._currentJob = null;
    }

    // Try to keep the pool at desired size
    if (!_isShuttingDown && _workers.length < _maxWorkers) {
      kDebugPrint('[KokoroPool] Respawning worker to maintain pool size...');
      unawaited(_startNewWorker());
    }
  }

  // Added for debugging worker lifecycle
  void _debugPrintWorkerStats() {
    // Reduced logging — only shown on interesting events (deaths, etc.) now to cut noise
    // kDebugPrint('[KokoroPool] Active workers: ${_workers.length}, spawning: $_spawningCount');
  }

  void _handleWorkerDeathByProcess(Process deadProcess) {
    final idx = _workers.indexWhere((w) => w.process == deadProcess);
    if (idx != -1) {
      _handleWorkerDeath(_workers[idx]);
    }
  }

  /// Eagerly start up to the configured number of workers (and let them load the model).
  /// Call this when Kokoro becomes the active engine to avoid cold-start delay on first speech.
  Future<void> warmUp() async {
    if (_isShuttingDown) return;

    final target = _maxWorkers;
    final toStart = target - (_workers.length + _spawningCount);

    kDebugPrint('[KokoroPool] warmUp: wanting $target workers, need to start $toStart');

    for (int i = 0; i < toStart; i++) {
      if (_workers.length + _spawningCount >= target) break;

      unawaited(_startNewWorker());

      // Slightly faster stagger than before (still safe)
      await Future.delayed(const Duration(milliseconds: 60));
    }
  }

  /// Shut down all workers. Called when TTS engine changes or app exits.
  Future<void> shutdown() async {
    _isShuttingDown = true;

    for (final w in _workers) {
      w.kill();
    }
    _workers.clear();

    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.complete(_GenerationResult(file: null, error: 'pool shutdown'));
      }
    }
    _pending.clear();
  }
}