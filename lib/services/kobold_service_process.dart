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

part of 'kobold_service.dart';

/// Process start/stop and console log ingest.
extension KoboldServiceProcess on KoboldService {
  Future<KoboldLaunchResult> _launch(
    String executablePath, {
    String? pickedModel,
    required int port,
  }) async {
    final b = _storageService.backendSettings;
    final launch = resolveKoboldLaunch(
      _storageService,
      pickedModel: pickedModel,
      engineDir: path.dirname(executablePath),
    );
    if (launch.note != null) _addLog(launch.note!);
    // A preset whose file is gone must not stay selected.
    if (launch.kcppsPath == null && (b.activeKcppsPath ?? '').isNotEmpty) {
      await b.setActiveKcppsPath(null);
    }
    if (!launch.canLaunch) {
      return KoboldLaunchResult.refused(
        launch.note ??
            'No model is chosen yet. Pick one in Settings, on the Backend tab.',
      );
    }
    // A start already under way would swallow this one without a word.
    if (_isStarting) {
      return const KoboldLaunchResult.refused('KoboldCpp is already starting.');
    }
    // Through the class member, not the body: test doubles override it.
    // The start is the one place a model or preset is checked, and it
    // says why when it refuses. Cleared first, so what is read back below
    // is this start's answer and never an earlier one's.
    _lastStartProblem = null;
    await startKobold(
      executablePath,
      launch.modelPath,
      kcppsPath: launch.kcppsPath,
      mmprojPath: launch.mmprojPath,
      port: port,
      gpuLayers: b.gpuLayers,
      contextSize: b.contextSize,
      useVulkan: b.useVulkan ?? false,
      useCublas: b.useCublas ?? false,
      useMetal: b.useMetal ?? false,
      useRocm: b.useRocm ?? false,
    );
    final refused = _lastStartProblem;
    if (refused != null) return KoboldLaunchResult.refused(refused);
    // The model that really started is the app's one record of "which
    // model": the status card, the vision lookup, the thinking settings,
    // an automatic restart and the web "loaded" marker all read it.
    if (b.lastUsedModelPath != launch.modelPath) {
      await b.setLastUsedModelPath(launch.modelPath);
    }
    return KoboldLaunchResult.started(launch.note);
  }

  Future<void> _startKobold(
    String executablePath,
    String modelPath, {
    String? kcppsPath,
    String? mmprojPath,
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
  }) async {
    if (_isStarting) return;
    // Claim the slot BEFORE the stop ladder below, not after it. That ladder
    // awaits for 1–6s with `_isRunning` already false, and a second caller
    // arriving in that window used to see both flags clear, walk straight to
    // Process.start, and have its handle overwritten by the first caller
    // resuming — one KoboldCpp process left with no owner, holding the port
    // and the VRAM. Every early return below must clear it again.
    _isStarting = true;
    _lastStartProblem = null;
    // If the previous process is still alive (e.g. stopKobold was not awaited
    // or the stop is racing with start), kill it first to prevent zombie
    // processes from accumulating — especially on Windows where port reuse
    // isn't immediate.
    if (_isRunning || _process != null) {
      debugPrint(
        '[KoboldService] startKobold called while still running — stopping first.',
      );
      try {
        await stopKobold();
        // Give the OS a moment to release the port
        await Future<void>.delayed(const Duration(seconds: 1));
      } catch (e) {
        // The slot is claimed above, so a throwing stop must release it or
        // no launch would ever be possible again this session.
        _isStarting = false;
        _addLog('Could not stop the previous backend: $e');
        notify();
        rethrow;
      }
    }

    // ── Model file pre-flight ────────────────────────────────────────────────
    // Verify the .gguf is genuinely readable BEFORE spawning KoboldCpp, so a
    // missing/placeholder/corrupt file produces a sentence the user can act on
    // instead of a bare "Process exited with code 2" (issue #137). Skipped when
    // modelPath is empty, which is preset mode — there the .kcpps owns the
    // model and KoboldCpp resolves it itself.
    //
    // This is the single choke point for every launch path: two of them
    // (LLMProvider.ensureManagedBackendIsRunning and the SetupService
    // autostart) previously did no existence check at all and would launch
    // straight into the same unexplained exit 2.
    final modelProblem = await ModelFileCheck.validate(modelPath);
    if (modelProblem != null) {
      _addLog(modelProblem);
      _lastStartProblem = modelProblem;
      _isStarting = false;
      notify();
      return;
    }

    // KoboldCpp before 1.112 stops at load on the staged config (it reads
    // the cache type as a number). Not supported: say so instead of
    // starting it to fail.
    final version = await KoboldBinaryVersion.versionFor(executablePath);
    if (!KoboldCapabilities.forVersion(version).quantKvAsText) {
      final problem =
          'This KoboldCpp ($version) is too old for the app. Update '
          'KoboldCpp to 1.112 or newer, then start it again.';
      _addLog(problem);
      _lastStartProblem = problem;
      _isStarting = false;
      notify();
      return;
    }

    // Store the executable path for cleanup
    _executablePath = executablePath;

    // Older versions left a one-setting batch file in the engine folder,
    // where it showed up as a preset. If it was picked, forget the pick.
    await removeLegacyBatchOverride(path.dirname(executablePath));
    if (kcppsPath != null && isAppOwnedKcpps(kcppsPath)) {
      await _storageService.backendSettings.setActiveKcppsPath(null);
      kcppsPath = null;
    }

    try {
      freeBeforeLaunch =
          await readFreeMemory?.call().timeout(const Duration(seconds: 5)) ??
          freeBeforeLaunch;
    } on Object catch (e) {
      _addLog('Free memory unknown before this start: $e');
    }

    final List<String> args;
    KoboldStagedRole? staged;
    try {
      args = await buildKoboldLaunchArgs(
        storage: _storageService,
        executablePath: executablePath,
        modelPath: modelPath,
        kcppsPath: kcppsPath,
        mmprojPath: mmprojPath,
        port: port,
        gpuLayers: gpuLayers,
        contextSize: contextSize,
        useVulkan: useVulkan,
        useCublas: useCublas,
        useMetal: useMetal,
        useRocm: useRocm,
        hardware: hardwareInfo?.call(),
        // Only asked for on a first run with no backend chosen. It can
        // take a while on Windows, so the status says what is happening.
        awaitHardware: hardwareWhenKnown == null
            ? null
            : () {
                _modelLoadingStatus = 'Checking your graphics card...';
                notify();
                return hardwareWhenKnown!();
              },
        free: freeBeforeLaunch,
        onNote: _addLog,
        onStaged: (s) => staged = s,
      );
    } on KoboldPresetProblem catch (e) {
      _addLog(e.message);
      _lastStartProblem = e.message;
      _isStarting = false;
      notify();
      return;
    } on Object catch (e) {
      // Anything else that stops the launch being prepared (the config
      // could not be written, a file changed under the read). The slot was
      // claimed above: left claimed, every later start returns at the top,
      // and nothing starts again until the app is restarted.
      final problem =
          'KoboldCpp was not started: its launch settings could '
          'not be prepared ($e).';
      _addLog(problem);
      _lastStartProblem = problem;
      _isStarting = false;
      notify();
      return;
    }

    try {
      print('AG_DEBUG: === STARTING KOBOLDCPP ===');
      print('AG_DEBUG: Executable: $executablePath');
      print('AG_DEBUG: Args: ${args.join(' ')}');
      print('AG_DEBUG: Working dir: ${path.dirname(executablePath)}');
      print('AG_DEBUG: File exists: ${File(executablePath).existsSync()}');
      print('AG_DEBUG: Model exists: ${File(modelPath).existsSync()}');

      // ROCm: consumer RDNA cards need HSA_OVERRIDE_GFX_VERSION or the
      // hipblas kernels abort at load — resolver detects the gfx arch and
      // supplies it (no-op when unnecessary or already exported).
      final extraEnv = useRocm
          ? await GpuBackendResolver.rocmEnvironment()
          : const <String, String>{};
      _lastFailure = null;
      _rocmFlashAttentionLaunch =
          useRocm && staged != null && _flashAttentionIn(staged!.key);
      _process = await Process.start(
        executablePath,
        args,
        workingDirectory: path.dirname(executablePath),
        environment: extraEnv.isEmpty ? null : extraEnv,
        includeParentEnvironment: true,
      );
      print('AG_DEBUG: Process started successfully! PID: ${_process!.pid}');
      _isRunning = true;
      _modelLoadingStatus = 'Initializing model...';
      _modelReady = false;
      _loadedModelPath = modelPath.isNotEmpty
          ? modelPath
          : _storageService.backendSettings.kcppsModelPath;
      _loadedKcppsPath = kcppsPath;
      _residentKey = staged?.key;
      _idleRestart();
      _loadGeneration++;
      _followLaunchContext(_loadGeneration);
      _addLog('Starting Koboldcpp...');
      _addLog('Command: $executablePath ${args.join(' ')}');
      notify();

      // Start periodic readiness probe — more reliable than log-watching.
      _startReadinessProbe();

      _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            _addLog(data);
            _parseLoadingStatus(data);
            _ingestLiveProgress(data);
            _storageService.backendSettings.noteKoboldOutput(data);
          });

      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen((data) {
            // Many backends log everything to stderr even if not an error.
            var cleanData = data.trim();
            if (cleanData.isNotEmpty) {
              // Strip ALL occurrences of ERR: and filter out progress dots
              cleanData = cleanData
                  .replaceAll('ERR: ', '')
                  .replaceAll('ERR:', '');
              if (cleanData != '.' && cleanData != '..' && cleanData != '...') {
                _addLog(cleanData);
                _parseLoadingStatus(cleanData);
                _ingestLiveProgress(cleanData);
              }
            }
          });

      final launched = _process!;
      launched.exitCode.then((code) {
        _addLog('Process exited with code $code');
        // Only the process we are still tracking may clear the state — a
        // late-dying orphan from an overlapping start must not report the
        // LIVE backend as stopped.
        if (!identical(_process, launched)) {
          notify();
          return;
        }
        final wasReady = _modelReady;
        _isRunning = false;
        _process = null;
        _residentKey = null;
        _loadGeneration++;
        // Exit 2 is KoboldCpp's "Cannot find text model file" path. The
        // pre-flight above catches most causes, but KoboldCpp resolves the
        // path through Python and can still reject a file we read fine, so
        // translate the bare exit code rather than leaving the user guessing.
        if (code == 2) {
          _addLog(ModelFileCheck.explainExitCode2(modelPath));
        }
        _noteExit(
          code,
          launched,
          wasReady: wasReady,
          executablePath: executablePath,
          port: port,
        );
        notify();
      });
    } catch (e, stack) {
      print('AG_DEBUG: === KOBOLDCPP START FAILED ===');
      print('AG_DEBUG: Error: $e');
      print('AG_DEBUG: Stack: $stack');
      _addLog('Failed to start process: $e');
      _isRunning = false;
      notify();
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  /// Regex matching KoboldCPP per-token / per-batch progress messages.
  /// These are purely informational counters that fire for every token and
  /// would otherwise flood the log with thousands of identical-looking lines.
  static final RegExp _progressLinePattern = RegExp(
    r'^(Generating \(|Processing Prompt(?: \[BATCH\])? \()',
    caseSensitive: false,
  );

  void _addLog(String data) {
    if (data.trim().isEmpty) return;

    // KoboldCPP uses bare \r (carriage return) to overwrite the current
    // terminal line.  Split on any combination of \r\n, \r, or \n so each
    // logical line is processed individually.
    final rawLines = data.split(RegExp(r'\r\n|\r|\n'));
    bool changed = false;

    for (final rawLine in rawLines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final isProgress = _progressLinePattern.hasMatch(line);

      if (isProgress && _logs.isNotEmpty) {
        final lastEntry = _logs.last;
        // If the last stored log entry is also a progress line, overwrite it
        // in-place rather than appending a new entry.  This keeps the list
        // at O(1) growth during a long generation instead of O(n).
        if (_progressLinePattern.hasMatch(lastEntry)) {
          _logs.last = line;
          changed = true;
          // Do NOT write progress lines to the file — they are noise.
          continue;
        }
      }

      _logs.add(line);
      if (!isProgress) _writeToLogFile(line + '\n');
      if (_logs.length > 1000) _logs.removeAt(0);
      changed = true;
    }

    if (changed) notify();
  }

  Future<void> _stopKobold() async {
    // Before anything else, and regardless of whether we own the process — a
    // hot-restart reconnect marks the model ready with `_process == null`,
    // and that verdict must not outlive the stop either. This also CANCELS a
    // measurement still on the wire: it is about to be a measurement of a
    // server that no longer exists, and it is holding this class's single
    // request slot while it waits. See [KoboldSystemRole.forget].
    _systemRole.forget();
    _idleStop();
    // Captured, because the exitCode listener installed by [startKobold] nulls
    // `_process` the moment the process dies — which can happen part-way
    // through the kill ladder below.
    final process = _process;
    if (process == null) return;
    // Its exit is the app's doing, not a failure.
    _stoppingProcess = process;
    _addLog('Stopping Backend (PID: ${process.pid})...');
    await terminateKoboldTree(
      process,
      executablePath: _executablePath,
      log: _addLog,
    );
    _process = null;
    _isRunning = false;
    _modelLoadingStatus = '';
    _modelReady = false;
    _loadedModelPath = null;
    _loadedKcppsPath = null;
    _residentKey = null;
    _loadGeneration++;
    _stopReadinessProbe();
    notify();
  }
}
