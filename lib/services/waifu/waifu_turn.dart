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

import 'package:front_porch_ai/services/waifu/waifu_fs.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_turn_contract.dart';

enum WaifuPhase { tools, verify, speak, done }

enum WaifuTurnStep { accept, retry, fail }

/// Nested explore/general result. Parent [absorbChild]s [turn].
class WaifuTurnReceipt {
  const WaifuTurnReceipt({required this.speech, required this.turn});

  final String speech;
  final WaifuTurn turn;
}

/// One send: live bubble + receipts + phase. Wrap-up is receipts, not English.
class WaifuTurn {
  WaifuTurn.start(
    String task,
    WaifuWriteRecord? initialWrite, {
    WaifuMode mode = WaifuMode.build,
    bool exploreOnly = false,
    bool enforceVerify = true,
  }) : contract = WaifuTurnContract.start(
         task,
         initialWrite,
         mode: mode,
         exploreOnly: exploreOnly,
         enforceVerify: enforceVerify,
       );

  final WaifuTurnContract contract;
  WaifuPhase phase = WaifuPhase.tools;
  WaifuMessage? live;
  String pendingSpeech = '';
  String failReason = '';

  bool get mutationRequired => contract.mutationRequired;
  bool get mutationSucceeded => contract.mutationSucceeded;
  bool get mutationAttempted => contract.mutationAttempted;
  bool get successfulTool => contract.successfulTool;
  bool get verified => contract.verified;
  bool get verifyRequired => contract.verifyRequired;
  bool get enforceVerify => contract.enforceVerify;
  bool get allowsPlanStepDone => contract.allowsPlanStepDone;
  int get mutationsSinceCheckIn => contract.mutationsSinceCheckIn;
  String get cue => contract.cue;
  Set<String> get mutatedPaths => contract.mutatedPaths;
  bool get canUseRememberedSpeech => contract.canUseRememberedSpeech;
  bool get canRetrySpeech => contract.canRetrySpeech;
  String get rememberedSpeech => contract.rememberedSpeech;

  bool get receiptsReady =>
      (!mutationRequired || mutationSucceeded) &&
      (!enforceVerify || !verifyRequired || verified);

  /// Empty tool list only when wrap-up is actually allowed.
  bool get speechOnly => phase == WaifuPhase.speak && receiptsReady;

  void noteAttempt(String toolName) => contract.noteAttempt(toolName);

  void noteResult(
    String toolName,
    WaifuToolResult result,
    WaifuWriteRecord? currentWrite, {
    Map<String, dynamic>? args,
  }) => contract.noteResult(toolName, result, currentWrite, args: args);

  void rememberToolSpeech(String body) => contract.rememberToolSpeech(body);

  void requestMutation() {
    phase = WaifuPhase.tools;
    contract.requestMutation();
  }

  void requestVerify() {
    phase = WaifuPhase.verify;
    contract.requestVerify();
  }

  void requestSpeech() {
    phase = WaifuPhase.speak;
    contract.requestSpeech();
  }

  void requestCheckInSpeech() {
    contract.requestCheckInSpeech();
    phase = enforceVerify && verifyRequired && !verified
        ? WaifuPhase.verify
        : WaifuPhase.speak;
  }

  void absorbChild(WaifuTurn child) => contract.absorbChild(child.contract);

  String failureLine(String body) => contract.failureLine(body);

  /// Empty-calls wrap-up. Loop only accepts, retries, or fails.
  WaifuTurnStep onEmptyCalls(String body) {
    rememberToolSpeech(body);
    switch (phase) {
      case WaifuPhase.tools:
        if (mutationRequired && !mutationSucceeded && !mutationAttempted) {
          return _retryOrFailMutation(body);
        }
        if (enforceVerify && verifyRequired && !verified) {
          return _retryOrFailVerify(body);
        }
        phase = WaifuPhase.speak;
        return _speak(body);
      case WaifuPhase.verify:
        if (enforceVerify && verifyRequired && !verified) {
          return _retryOrFailVerify(body);
        }
        phase = WaifuPhase.speak;
        return _speak(body);
      case WaifuPhase.speak:
        return _speak(body);
      case WaifuPhase.done:
        pendingSpeech = body.trim().isEmpty ? rememberedSpeech : body;
        return WaifuTurnStep.accept;
    }
  }

  WaifuTurnStep _retryOrFailMutation(String body) {
    if (contract.mutationCorrectionAttempts < kWaifuTurnCorrectionAttempts) {
      requestMutation();
      return WaifuTurnStep.retry;
    }
    failReason = 'no file change landed for a code-change request';
    pendingSpeech = failureLine(body);
    phase = WaifuPhase.done;
    return WaifuTurnStep.fail;
  }

  WaifuTurnStep _retryOrFailVerify(String body) {
    if (contract.verifyCorrectionAttempts < kWaifuTurnCorrectionAttempts) {
      requestVerify();
      return WaifuTurnStep.retry;
    }
    failReason = 'no verify after a project file change';
    pendingSpeech = failureLine(body);
    phase = WaifuPhase.done;
    return WaifuTurnStep.fail;
  }

  WaifuTurnStep _speak(String body) {
    final trimmed = body.trim();
    final todoOk =
        contract.todoWriteSucceeded || !waifuLooksTodoReceiptClaim(trimmed);
    if (!todoOk) {
      if (contract.todoCorrectionAttempts < kWaifuTurnCorrectionAttempts) {
        contract.requestTodoWrite();
        phase = WaifuPhase.tools;
        return WaifuTurnStep.retry;
      }
      failReason = 'no todowrite receipt for a claimed todo update';
      pendingSpeech = failureLine(body);
      phase = WaifuPhase.done;
      return WaifuTurnStep.fail;
    }
    if (trimmed.isEmpty) {
      if (canUseRememberedSpeech) {
        pendingSpeech = rememberedSpeech;
        phase = WaifuPhase.done;
        return WaifuTurnStep.accept;
      }
      if (canRetrySpeech) {
        requestSpeech();
        return WaifuTurnStep.retry;
      }
      failReason = 'tool work ended without an in-character spoken line';
      pendingSpeech = failureLine(body);
      phase = WaifuPhase.done;
      return WaifuTurnStep.fail;
    }
    pendingSpeech = trimmed;
    phase = WaifuPhase.done;
    return WaifuTurnStep.accept;
  }
}
