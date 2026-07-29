import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/services/backend_manager.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';

enum SetupStep {
  idle,
  checkingBackend,
  downloadingBackend,
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

  SetupService(
    this._storageService,
    this._backendManager,
    this._koboldService,
  );

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

      // Remote backends never need a local KoboldCpp binary. Skip the ~100MB+
      // download (and the overlay) so first boot for OpenRouter/OMLX users —
      // and the E2E smoke suite, which runs against an in-process fake remote —
      // is not blocked on a network fetch that can OOM or flake under CI.
      final backendType = _storageService.backendType;
      final isLocalBackend =
          backendType != 'openRouter' && backendType != 'omlx';
      if (!isLocalBackend) {
        _currentStep = SetupStep.complete;
        notifyListeners();
        return;
      }

      // 2. Check and Download Backend if missing (local backend only)
      await _backendManager.checkBackendAvailability();
      if (_backendManager.backendPath == null) {
        _currentStep = SetupStep.downloadingBackend;
        notifyListeners();

        await _backendManager.downloadBackend();

        if (_backendManager.backendPath == null) {
          throw Exception(_backendManager.error ?? 'Failed to install backend');
        }
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
      final modelPath = _storageService.lastUsedModelPath;
      final presetOwnsModel =
          _storageService.kcppsHasModel &&
          _storageService.kcppsModelFileExists;

      if (_storageService.autostartBackend &&
          (modelPath != null || presetOwnsModel)) {
        _currentStep = SetupStep.startingBackend;
        notifyListeners();

        await _koboldService.startKobold(
          _backendManager.backendPath!,
          modelPath ?? '',
          kcppsPath: _storageService.activeKcppsPath,
          mmprojPath: modelPath != null
              ? _storageService.mmprojForModel(modelPath)
              : null,
          gpuLayers: _storageService.gpuLayers,
          contextSize: _storageService.contextSize,
          useVulkan: _storageService.useVulkan ?? false,
          useCublas: _storageService.useCublas ?? false,
          useMetal: _storageService.useMetal ?? false,
          useRocm: _storageService.useRocm ?? false,
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

  void reset() {
    _currentStep = SetupStep.idle;
    _errorMessage = null;
    notifyListeners();
  }
}
