import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

enum SetupStep {
  idle,
  checkingBackend,

  /// First launch, nothing installed, no choice recorded yet: the overlay
  /// shows the one-time "how will you run your AI?" choice instead of
  /// touching the network. Boot NEVER downloads on its own anymore.
  firstRunChoice,
  startingBackend,
  complete,
  error,
}

class SetupService extends ChangeNotifier {
  final StorageService _storageService;
  final BackendManager _backendManager;
  final KoboldService _koboldService;

  SetupStep _currentStep = SetupStep.idle;
  String? _errorMessage;

  SetupStep get currentStep => _currentStep;
  String? get errorMessage => _errorMessage;

  SetupService(this._storageService, this._backendManager, this._koboldService);

  Future<void> runAutoSetup() async {
    if (_currentStep != SetupStep.idle && _currentStep != SetupStep.error) {
      return;
    }

    // Intel Macs cannot run KoboldCpp — skip download and autostart entirely
    if (_backendManager.isIntelMac) {
      _currentStep = SetupStep.complete;
      notifyListeners();
      return;
    }

    _errorMessage = null;
    _currentStep = SetupStep.checkingBackend;
    notifyListeners();

    try {
      // 1. Wait for StorageService to fully initialize (SharedPreferences loaded)
      await _storageService.initialized;

      // Remote/own backends never need a local KoboldCpp binary. Skip
      // everything (and record the implicit choice) so first boot for
      // OpenRouter/OMLX users — and the E2E smoke suite, which runs against
      // an in-process fake remote — never touches the network.
      final backendType = _storageService.backendSettings.backendType;
      final isLocalBackend =
          backendType != 'openRouter' && backendType != 'omlx';
      if (!isLocalBackend) {
        if (!_storageService.backendSettings.backendChoiceDone) {
          await _storageService.backendSettings.setBackendChoiceDone(true);
        }
        _currentStep = SetupStep.complete;
        notifyListeners();
        return;
      }

      // 2. Locate an existing engine. Boot NEVER downloads on its own — the
      //    blocking "Downloading Backend…" overlay that held the whole app
      //    hostage on first launch is gone.
      await _backendManager.checkBackendAvailability();
      if (_backendManager.backendPath == null) {
        if (!_storageService.backendSettings.backendChoiceDone) {
          // Genuine first launch: ask intent (one tap), then the overlay
          // dismisses and any download runs in the background.
          _currentStep = SetupStep.firstRunChoice;
          notifyListeners();
          return;
        }
        // Choice already made in favour of the managed engine but the binary
        // is missing (bin dir wiped, download interrupted last session):
        // re-acquire in the background — the engine chip shows progress.
        unawaited(_backendManager.ensureEngineInstalled());
        _currentStep = SetupStep.complete;
        notifyListeners();
        return;
      }

      // An installed engine IS the choice — never show the first-run ask.
      if (!_storageService.backendSettings.backendChoiceDone) {
        await _storageService.backendSettings.setBackendChoiceDone(true);
      }

      // 3. Dismiss overlay so the user can interact with the app
      _currentStep = SetupStep.complete;
      notifyListeners();

      // 4. Wait 5 seconds before attempting autostart (gives the app UI time to settle)
      await Future.delayed(const Duration(seconds: 5));

      // 5. Autostart the local Kobold backend when it was the last one used.
      //    This covers both a plain model file (lastUsedModelPath) and a
      //    .kcpps preset that owns the model — the preset used to be its own
      //    "pseudoRemote" backend, but it is now just a launch option of the
      //    local backend, so a single autostart branch handles both.
      final modelPath = _storageService.backendSettings.lastUsedModelPath;
      final presetOwnsModel =
          _storageService.backendSettings.kcppsHasModel &&
          _storageService.backendSettings.kcppsModelFileExists;

      if (_storageService.backendSettings.autostartBackend &&
          (modelPath != null || presetOwnsModel)) {
        _currentStep = SetupStep.startingBackend;
        notifyListeners();

        await _koboldService.startKobold(
          _backendManager.backendPath!,
          modelPath ?? '',
          kcppsPath: _storageService.backendSettings.activeKcppsPath,
          mmprojPath: modelPath != null
              ? _storageService.presetSettings.modelMmprojMap[modelPath]
              : null,
          gpuLayers: _storageService.backendSettings.gpuLayers,
          contextSize: _storageService.backendSettings.contextSize,
          useVulkan: _storageService.backendSettings.useVulkan ?? false,
          useCublas: _storageService.backendSettings.useCublas ?? false,
          useMetal: _storageService.backendSettings.useMetal ?? false,
          useRocm: _storageService.backendSettings.useRocm ?? false,
        );

        _currentStep = SetupStep.complete;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = e.toString();
      _currentStep = SetupStep.error;
      notifyListeners();
    }
  }

  /// First-run choice: run the managed KoboldCpp engine. Also the "Not sure
  /// yet" path — it's the app's default, and starting the fetch NOW (in the
  /// background) is the whole point: by the time a model is downloaded and a
  /// chat begins, the engine is already there. Dismisses the overlay
  /// immediately; the engine chip carries the progress.
  Future<void> chooseManagedEngine() async {
    await _storageService.backendSettings.setBackendChoiceDone(true);
    unawaited(_backendManager.ensureEngineInstalled());
    _currentStep = SetupStep.complete;
    notifyListeners();
  }

  /// First-run choice: the user brings their own backend (OpenRouter,
  /// Nano-GPT, oMLX, LM Studio, or any OpenAI-compatible API — local or
  /// cloud). No engine download, ever; backendType flips to the API kind and
  /// the details are configured in Settings → Backend.
  Future<void> chooseOwnBackend() async {
    await _storageService.backendSettings.setBackendType('openRouter');
    await _storageService.backendSettings.setBackendChoiceDone(true);
    _currentStep = SetupStep.complete;
    notifyListeners();
  }

  void reset() {
    _currentStep = SetupStep.idle;
    _errorMessage = null;
    notifyListeners();
  }
}
