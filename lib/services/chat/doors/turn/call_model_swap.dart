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

import 'package:front_porch_ai/services/chat/doors/turn/prompt_deps.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// The voice call's model swap (the safe speed lane): sendMessage parks the
/// main model before the pre-generation evals, and the request build adopts
/// the parked name into the turn ([GenTurn.originalModelName]), whose
/// restore sites (postgen, stream-cancel, catch) put the main model back.
class CallModelSwap {
  CallModelSwap(this._d);

  final PromptDeps _d;

  /// Main model parked by the pre-turn swap until the request phase adopts
  /// it into the turn carrier.
  String? parkedOriginal;

  StorageService get _storageService => _d.services.storage;
  LLMProvider? get _llmProvider => _d.services.llmProvider();
  bool get _callMode => _d.doors.controls().callMode;
  String? get _callEvalModelOriginal => parkedOriginal;
  set _callEvalModelOriginal(String? v) => parkedOriginal = v;

  /// Pre-turn half of the call-model swap (voice call safe speed lane): the
  /// old swap fired only in the request phase, so every pre-generation LLM
  /// call of a voice turn — the realism judges, the time eval, the
  /// objective check — still waited on the full-size main model, which is
  /// where the "Thinking…" silence actually lived. sendMessage enters the
  /// swap before that work; the request phase adopts it into
  /// [GenTurn.originalModelName], whose existing restore sites (postgen,
  /// stream-cancel, catch) put the main model back. Same gate as the
  /// in-request swap — every backend that carries the model as a request
  /// parameter (remote APIs AND oMLX, which rides openRouterService;
  /// isLocal is true only for managed KoboldCpp, where a swap would mean a
  /// process restart per turn).
  void enter() {
    if (_callEvalModelOriginal != null) return; // already parked this turn
    if (!_callMode ||
        _storageService.sttSettings.callModelName.isEmpty ||
        _llmProvider == null ||
        _llmProvider!.isLocal) {
      return;
    }
    _callEvalModelOriginal = _llmProvider!.openRouterService.modelName;
    _llmProvider!.openRouterService.configure(
      modelName: _storageService.sttSettings.callModelName,
    );
  }

  /// Abandon half: restores the main model when a swapped turn never reaches
  /// the request phase (eval cancelled) or the call ends with a swap parked
  /// (the callMode setter calls this on every call end, belt and braces).
  void exit() {
    final original = _callEvalModelOriginal;
    if (original == null || _llmProvider == null) return;
    _callEvalModelOriginal = null;
    _llmProvider!.openRouterService.configure(modelName: original);
  }
}
