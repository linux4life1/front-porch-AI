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
  error
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
    if (_currentStep != SetupStep.idle && _currentStep != SetupStep.error) return;

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

      // 2. Check and Download Backend if missing
      await _backendManager.checkBackendAvailability();
      if (_backendManager.backendPath == null) {
        _currentStep = SetupStep.downloadingBackend;
        notifyListeners();
        
        // Use the existing listener in BackendManager or just wait for it?
        // Let's call download and wait.
        // We'll add a listener to BackendManager to know when it's done.
        void listener() {
           if (!_backendManager.isDownloading && _backendManager.backendPath != null) {
             // Success
           }
        }
        _backendManager.addListener(listener);
        
        await _backendManager.downloadBackend();
        _backendManager.removeListener(listener);

        if (_backendManager.backendPath == null) {
          throw Exception(_backendManager.error ?? 'Failed to install backend');
        }
      }

      // 3. Autostart Backend only if local mode was last used
      final isLocalBackend = _storageService.backendType != 'openRouter';
      if (isLocalBackend && _storageService.autostartBackend && _storageService.lastUsedModelPath != null) {
        _currentStep = SetupStep.startingBackend;
        notifyListeners();

        await _koboldService.startKobold(
          _backendManager.backendPath!,
          _storageService.lastUsedModelPath!,
          kcppsPath: _storageService.activeKcppsPath,
          gpuLayers: _storageService.gpuLayers,
          contextSize: _storageService.contextSize,
          useVulkan: _storageService.useVulkan ?? false,
          useCublas: _storageService.useCublas ?? false,
          useMetal: _storageService.useMetal ?? false,
          useRocm: _storageService.useRocm ?? false,
        );
      }

      _currentStep = SetupStep.complete;
      notifyListeners();
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
