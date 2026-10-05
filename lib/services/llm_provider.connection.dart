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

part of 'llm_provider.dart';

/// Why the last start of the app's KoboldCpp was refused, and what the
/// engine had loaded then (see [LLMProviderConnection.composerConnectionHint]).
final Expando<({String words, int generation})> _providerStartRefusal =
    Expando<({String words, int generation})>('fpai.startRefusal');

/// What the chat screen says about the connection when the app's own start of
/// KoboldCpp was refused.
extension LLMProviderConnection on LLMProvider {
  /// Starts the app's KoboldCpp for chat entry or for a swap, and keeps what
  /// the start said, for [composerConnectionHint]. Null when nothing needed
  /// starting.
  Future<KoboldLaunchResult?> _ensureManagedKobold({
    bool forGpuSwap = false,
    String? modelPath,
    String? kcppsPath,
  }) async {
    final result = await _startManagedKobold(
      forGpuSwap: forGpuSwap,
      modelPath: modelPath,
      kcppsPath: kcppsPath,
    );
    if (result != null) _noteStart(result);
    return result;
  }

  void _noteStart(KoboldLaunchResult result) {
    // A start refused because another is under way says nothing about how
    // that one ends.
    if (_koboldService.isStarting) return;
    final words = result.refusal;
    final before = _providerStartRefusal[this]?.words;
    _providerStartRefusal[this] = words == null
        ? null
        : (words: words, generation: _koboldService.loadGeneration);
    if (before != words) _onServiceChanged();
  }

  /// In place of "No API connection": why the app's start of KoboldCpp was
  /// refused, in plain words. Null while it runs or starts, and once what the
  /// engine has loaded has changed since the refusal (it was started some
  /// other way, and stopped), which makes the refusal no longer why nothing
  /// runs.
  String? get composerConnectionHint {
    if (!hasManagedProcess || composerConnectionReady) return null;
    final refusal = _providerStartRefusal[this];
    return refusal != null &&
            refusal.generation == _koboldService.loadGeneration
        ? refusal.words
        : null;
  }
}
