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
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';

const kWaifuTurnCorrectionAttempts = 2;

const kWaifuReceiptMutationTools = {
  kWaifuToolEdit,
  kWaifuToolApplyPatch,
  kWaifuToolWrite,
};

enum WaifuFinalAction {
  accept,
  useRememberedSpeech,
  retryMutation,
  retrySpeech,
  failMutation,
  failSpeech,
}

bool waifuTaskRequestsFileChange(String task) {
  final lower = task.toLowerCase();
  final strong = RegExp(
    r'\b(edit|implement|modify|patch|refactor|rewrite|scaffold)\b',
  ).hasMatch(lower);
  if (strong) return true;
  final changeVerb = RegExp(
    r'\b(add|build|change|create|delete|fix|make|move|remove|rename|replace|'
    r'update|wire|write)\b',
  ).hasMatch(lower);
  final codeTarget = RegExp(
    r'\b(api|app|bug|button|class|code|component|dialog|docs?|endpoint|'
    r'feature|field|file|function|handler|menu|method|module|page|project|'
    r'repo|route|screen|service|setting|style|test|ui|widget)\b|'
    r'\b[\w.-]+\.(dart|js|jsx|ts|tsx|py|rs|go|java|kt|swift|'
    r'c|cc|cpp|h|hpp|cs|rb|php|lua|sh|yaml|yml|json|toml|md|txt)\b',
  ).hasMatch(lower);
  return changeVerb && codeTarget;
}

bool waifuLooksGenericCompletion(String body) {
  final normalized = body.trim().toLowerCase().replaceAll(
    RegExp(r'[.!…\s]+$'),
    '',
  );
  return normalized.isEmpty ||
      RegExp(
        r"^(done|finished|complete|completed|all set|fixed|implemented|updated|"
        r"patched|wrote it|i(?:'ve| have) (?:fixed|updated|patched|finished) "
        r"(?:it|the file|the code)|(?:wrote|patched|fixed|updated|implemented) "
        r"(?:the )?[\w./-]+|applied (?:the )?(?:patch|changes)|"
        r"changes? (?:applied|saved))$",
      ).hasMatch(normalized);
}

class WaifuTurnContract {
  WaifuTurnContract.start(String task, WaifuWriteRecord? initialWrite)
    : mutationRequired = waifuTaskRequestsFileChange(task),
      _initialWrite = initialWrite;

  final bool mutationRequired;
  final WaifuWriteRecord? _initialWrite;
  bool mutationAttempted = false;
  bool mutationSucceeded = false;
  bool successfulTool = false;
  bool speechOnly = false;
  int mutationCorrectionAttempts = 0;
  int speechCorrectionAttempts = 0;
  String rememberedSpeech = '';
  String cue = '';

  bool get canRetrySpeech =>
      speechCorrectionAttempts < kWaifuTurnCorrectionAttempts;
  bool get canUseRememberedSpeech =>
      rememberedSpeech.isNotEmpty && (!mutationRequired || mutationSucceeded);

  void rememberToolSpeech(String body) {
    final trimmed = body.trim();
    if (trimmed.isNotEmpty && !waifuLooksGenericCompletion(trimmed)) {
      rememberedSpeech = trimmed;
    }
  }

  void noteAttempt(String toolName) {
    if (kWaifuReceiptMutationTools.contains(toolName)) {
      mutationAttempted = true;
    }
  }

  void noteResult(
    String toolName,
    WaifuToolResult result,
    WaifuWriteRecord? currentWrite,
  ) {
    successfulTool = successfulTool || result.ok;
    if (kWaifuReceiptMutationTools.contains(toolName) && result.write != null) {
      mutationSucceeded = true;
    }
    if (result.ok && !identical(currentWrite, _initialWrite)) {
      mutationSucceeded = true;
    }
    if (mutationSucceeded) cue = '';
  }

  WaifuFinalAction decideFinal(String body) {
    final trimmed = body.trim();
    final generic = waifuLooksGenericCompletion(trimmed);
    if (mutationRequired && !mutationSucceeded && !mutationAttempted) {
      rememberToolSpeech(trimmed);
      return mutationCorrectionAttempts < kWaifuTurnCorrectionAttempts
          ? WaifuFinalAction.retryMutation
          : WaifuFinalAction.failMutation;
    }
    if (trimmed.isEmpty ||
        (generic && successfulTool) ||
        (generic && mutationRequired && !mutationSucceeded)) {
      if (canUseRememberedSpeech) {
        return WaifuFinalAction.useRememberedSpeech;
      }
      return speechCorrectionAttempts < kWaifuTurnCorrectionAttempts
          ? WaifuFinalAction.retrySpeech
          : (mutationRequired && !mutationSucceeded
                ? WaifuFinalAction.failMutation
                : WaifuFinalAction.failSpeech);
    }
    return WaifuFinalAction.accept;
  }

  void requestMutation() {
    mutationCorrectionAttempts++;
    speechOnly = false;
    cue =
        'TURN CONTRACT: The user asked for a code/file change, but no '
        'write, edit, or apply_patch receipt landed. Do the real change with '
        'a file tool now; personality without a patch is not completion.';
  }

  void requestSpeech() {
    speechCorrectionAttempts++;
    speechOnly = true;
    cue =
        'TURN CONTRACT: Tool work is over. Give one short spoken wrap-up in '
        'the selected card’s diction now. No tool call, source dump, generic '
        '“Done”, or empty answer.';
  }

  String failureLine(String body) {
    if (mutationRequired && !mutationSucceeded) {
      return 'I could not put a real change on disk, so I stopped instead of '
          'pretending I did.';
    }
    if (canUseRememberedSpeech) return rememberedSpeech;
    final trimmed = body.trim();
    if (trimmed.isNotEmpty && !waifuLooksGenericCompletion(trimmed)) {
      return trimmed;
    }
    if (mutationSucceeded) {
      return 'The work reached disk, but I lost the words for the porch report.';
    }
    return 'I stopped without a proper porch report instead of leaving an '
        'empty bubble.';
  }
}
