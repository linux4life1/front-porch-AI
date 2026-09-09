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

import 'package:front_porch_ai/services/waifu/waifu_checkin.dart';
import 'package:front_porch_ai/services/waifu/waifu_fs.dart';
import 'package:front_porch_ai/services/waifu/waifu_plan.dart';
import 'package:front_porch_ai/services/waifu/waifu_session.dart';
import 'package:front_porch_ai/services/waifu/waifu_sit_down.dart';
import 'package:front_porch_ai/services/waifu/waifu_tools.dart';

const kWaifuTurnCorrectionAttempts = 2;

const kWaifuReceiptMutationTools = {
  kWaifuToolEdit,
  kWaifuToolApplyPatch,
  kWaifuToolWrite,
};

const kWaifuBuildVerifyCue =
    'After write, edit, or apply_patch changes a project file, re-read '
    'that path or run a project test/analyze command before claiming the '
    'work done. An accepted-plan step stays pending until both land. '
    'Prefer the built-in run-plan-step workflow when a plan is pinned.';

enum WaifuFinalAction {
  accept,
  useRememberedSpeech,
  retryMutation,
  retrySpeech,
  retryVerify,
  failMutation,
  failSpeech,
  failVerify,
  retryTodoWrite,
  failTodoWrite,
}

String waifuNormalizeVerifyPath(String path) =>
    path.trim().replaceAll('\\', '/').replaceFirst(RegExp(r'^\./'), '');

bool waifuReadVerifiesMutate(String readPath, Iterable<String> mutated) {
  final want = waifuNormalizeVerifyPath(readPath);
  if (want.isEmpty) return false;
  for (final raw in mutated) {
    final have = waifuNormalizeVerifyPath(raw);
    if (have.isEmpty) continue;
    if (have == want) return true;
    if (have.endsWith('/$want') || want.endsWith('/$have')) return true;
  }
  return false;
}

/// Test/analyze class only. `echo`, `ls`, and `test -f` are not verify.
/// Every `&&` / `||` / `;` segment is scanned so `cd pkg && flutter test`
/// receipts. `--help` / `-h` / dry-run anywhere in the command (or any
/// segment) fails the whole receipt — a later clean segment is not an
/// escape (`flutter test --help || flutter test`).
bool waifuLooksVerifyCommand(String command) {
  final lowered = command.trim().toLowerCase();
  final segments = lowered.split(RegExp(r'(?:&&|\|\||[;|\n])'));
  List<String> wordsOf(String raw) => raw
      .replaceAll(RegExp(r'''["'`(){}\[\],;|&<>]'''), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();
  bool theater(List<String> words) => words.any((w) {
    if (w == '-h' || w == '--help' || w.startsWith('--help')) return true;
    return w == '--dry-run' ||
        w == '--dryrun' ||
        w == '--dry_run' ||
        w.startsWith('--dry-run') ||
        w.startsWith('--dryrun');
  });
  if (theater(wordsOf(lowered))) return false;
  for (final segment in segments) {
    if (theater(wordsOf(segment))) return false;
  }
  for (final segment in segments) {
    final words = wordsOf(segment);
    if (words.isEmpty) continue;
    var cmd = words.first;
    if (cmd.contains('/')) cmd = cmd.split('/').last;
    if (cmd == 'npx' && words.length > 1) {
      if (const {'vitest', 'jest', 'eslint'}.contains(words[1])) return true;
      continue;
    }
    if (cmd == 'flutter' || cmd == 'dart') {
      if (words.length > 1 && const {'test', 'analyze'}.contains(words[1])) {
        return true;
      }
      continue;
    }
    if (cmd == 'cargo') {
      if (words.length > 1 && const {'test', 'clippy'}.contains(words[1])) {
        return true;
      }
      continue;
    }
    if (cmd == 'go') {
      if (words.length > 1 && words[1] == 'test') return true;
      continue;
    }
    if (cmd == 'make') {
      if (words.length > 1 &&
          const {'test', 'check', 'lint'}.contains(words[1])) {
        return true;
      }
      continue;
    }
    if (cmd == 'npm' || cmd == 'pnpm' || cmd == 'yarn') {
      if (words.length > 1 && words[1] == 'test') return true;
      if (words.length > 2 && words[1] == 'run') {
        final script = words[2];
        if (script == 'test' ||
            script == 'lint' ||
            script == 'analyze' ||
            script.startsWith('test:')) {
          return true;
        }
      }
      continue;
    }
    if (cmd == 'python' || cmd == 'python3' || cmd == 'py') {
      if (words.length > 2 &&
          words[1] == '-m' &&
          const {'pytest', 'unittest'}.contains(words[2])) {
        return true;
      }
      continue;
    }
    if (const {'pytest', 'vitest', 'jest'}.contains(cmd)) return true;
  }
  return false;
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

bool waifuLooksTodoReceiptClaim(String body) {
  final lower = body.toLowerCase();
  if (RegExp(r'\btodowrite\b').hasMatch(lower)) return true;
  final list = RegExp(r'\b(?:todo|to-do|task) lists?\b').hasMatch(lower);
  final updated = RegExp(
    r'\b(?:updated?|wrote|replaced|rewrote|changed)\b',
  ).hasMatch(lower);
  final todo = RegExp(r'\b(?:todos?|to-dos?)\b').hasMatch(lower);
  if ((list || todo) && updated) return true;
  final done = RegExp(
    r'\b(?:completed?|finished|checked\s+off|marked\s+(?:as\s+)?done)\b',
  ).hasMatch(lower);
  return todo && done;
}

bool waifuTurnHasTodoWriteReceipt(Iterable<WaifuToolChip> chips) {
  for (final chip in chips) {
    if (chip.pending || !chip.ok) continue;
    if (canonicalWaifuToolName(chip.name) == kWaifuToolTodoWrite) return true;
  }
  return false;
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
  WaifuTurnContract.start(
    String task,
    WaifuWriteRecord? initialWrite, {
    this.mode = WaifuMode.build,
    bool exploreOnly = false,
    this.enforceVerify = true,
  }) : mutationRequired =
           (!exploreOnly && mode == WaifuMode.plan) ||
           waifuTaskRequestsFileChange(task),
       _initialWrite = initialWrite;

  final WaifuMode mode;
  final bool mutationRequired;
  final bool enforceVerify;
  final WaifuWriteRecord? _initialWrite;
  final mutatedPaths = <String>{};
  final readPaths = <String>{};
  bool mutationAttempted = false;
  bool mutationSucceeded = false;
  bool verifyRequired = false;
  bool verified = false;
  bool successfulTool = false;
  bool todoWriteSucceeded = false;
  bool todoWriteRequired = false;
  int mutationsSinceCheckIn = 0;
  bool checkInWrapUp = false;
  bool speechOnly = false;
  int mutationCorrectionAttempts = 0;
  int speechCorrectionAttempts = 0;
  int verifyCorrectionAttempts = 0;
  int todoCorrectionAttempts = 0;
  String rememberedSpeech = '';
  String cue = '';

  bool get canRetrySpeech =>
      speechCorrectionAttempts < kWaifuTurnCorrectionAttempts;
  bool get canUseRememberedSpeech =>
      rememberedSpeech.isNotEmpty &&
      (checkInWrapUp ||
          ((!mutationRequired || mutationSucceeded) &&
              (!verifyRequired || verified)));
  bool get allowsPlanStepDone => mutationSucceeded && verified;

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
    WaifuWriteRecord? currentWrite, {
    Map<String, dynamic>? args,
  }) {
    successfulTool = successfulTool || result.ok;
    if (toolName == kWaifuToolTodoWrite && result.ok) {
      todoWriteSucceeded = true;
      todoWriteRequired = false;
      cue = '';
    }
    if (toolName == kWaifuToolQuestion && result.ok) {
      mutationsSinceCheckIn = 0;
    }
    if (kWaifuReceiptMutationTools.contains(toolName) && result.write != null) {
      mutationsSinceCheckIn++;
      if (mode != WaifuMode.plan ||
          waifuRelativeIsPlanArtifact(result.write!.relativePath)) {
        mutationSucceeded = true;
      }
      if (mode != WaifuMode.plan &&
          !waifuRelativeIsPlanArtifact(result.write!.relativePath)) {
        mutatedPaths.add(waifuNormalizeVerifyPath(result.write!.relativePath));
        verifyRequired = true;
        readPaths.clear();
        verified = false;
      }
    }
    if (result.ok &&
        !identical(currentWrite, _initialWrite) &&
        (mode != WaifuMode.plan ||
            (currentWrite != null &&
                waifuRelativeIsPlanArtifact(currentWrite.relativePath)))) {
      mutationSucceeded = true;
    }
    if (result.ok && args != null) {
      if (toolName == kWaifuToolRead) {
        final path = waifuToolPathArg(args);
        if (path != null) readPaths.add(waifuNormalizeVerifyPath(path));
      }
      if (toolName == kWaifuToolBash &&
          waifuLooksVerifyCommand(
            (args['command'] ?? args['cmd'] ?? '').toString(),
          )) {
        noteVerify();
      }
    }
    if (!verified &&
        readPaths.any((r) => waifuReadVerifiesMutate(r, mutatedPaths))) {
      noteVerify();
    }
    if (mutationSucceeded && (!verifyRequired || verified)) cue = '';
  }

  void noteVerify() {
    verified = true;
    if (verifyRequired) cue = '';
  }

  void absorbChild(WaifuTurnContract child) {
    successfulTool = successfulTool || child.successfulTool;
    mutationAttempted = mutationAttempted || child.mutationAttempted;
    if (child.todoWriteSucceeded) {
      todoWriteSucceeded = true;
      todoWriteRequired = false;
    }
    if (child.mutationSucceeded) mutationSucceeded = true;
    if (child.verifyRequired) verifyRequired = true;
    if (child.mutatedPaths.isNotEmpty) {
      readPaths.clear();
      verified = false;
    }
    mutatedPaths.addAll(child.mutatedPaths);
    readPaths.addAll(child.readPaths);
    mutationsSinceCheckIn += child.mutationsSinceCheckIn;
    if (child.verified) {
      noteVerify();
      return;
    }
    if (!verified &&
        readPaths.any((r) => waifuReadVerifiesMutate(r, mutatedPaths))) {
      noteVerify();
    }
  }

  WaifuFinalAction decideFinal(
    String body, {
    List<WaifuToolChip> chips = const [],
  }) {
    final trimmed = body.trim();
    final generic = waifuLooksGenericCompletion(trimmed);
    if (checkInWrapUp) {
      if (trimmed.isEmpty || generic) {
        if (rememberedSpeech.isNotEmpty) {
          return WaifuFinalAction.useRememberedSpeech;
        }
        return speechCorrectionAttempts < kWaifuTurnCorrectionAttempts
            ? WaifuFinalAction.retrySpeech
            : WaifuFinalAction.failSpeech;
      }
      return WaifuFinalAction.accept;
    }
    if (mutationRequired && !mutationSucceeded && !mutationAttempted) {
      rememberToolSpeech(trimmed);
      return mutationCorrectionAttempts < kWaifuTurnCorrectionAttempts
          ? WaifuFinalAction.retryMutation
          : WaifuFinalAction.failMutation;
    }
    if (enforceVerify && verifyRequired && !verified) {
      rememberToolSpeech(trimmed);
      return verifyCorrectionAttempts < kWaifuTurnCorrectionAttempts
          ? WaifuFinalAction.retryVerify
          : WaifuFinalAction.failVerify;
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
    final todoReceipt =
        todoWriteSucceeded || waifuTurnHasTodoWriteReceipt(chips);
    if (waifuLooksTodoReceiptClaim(trimmed) && !todoReceipt) {
      return todoCorrectionAttempts < kWaifuTurnCorrectionAttempts
          ? WaifuFinalAction.retryTodoWrite
          : WaifuFinalAction.failTodoWrite;
    }
    return WaifuFinalAction.accept;
  }

  void requestMutation() {
    mutationCorrectionAttempts++;
    speechOnly = false;
    cue = mode == WaifuMode.plan
        ? 'TURN CONTRACT: Plan mode needs a real $kWaifuPlansDir/<slug>.md '
              'receipt (write, edit, or apply_patch). Exploring or talking '
              'without that artifact is not completion.'
        : 'TURN CONTRACT: The user asked for a code/file change, but no '
              'write, edit, or apply_patch receipt landed. Do the real change '
              'with a file tool now; personality without a patch is not '
              'completion.';
  }

  void requestTodoWrite() {
    todoCorrectionAttempts++;
    todoWriteRequired = true;
    speechOnly = false;
    cue =
        'TURN CONTRACT: You claimed a todo update (completed, todowrite, or '
        'the todo list), but no successful todowrite landed this turn. Call '
        'todowrite for real, or stop claiming the list changed. Thoughts are '
        'not a receipt.';
  }

  void requestSpeech() {
    speechCorrectionAttempts++;
    speechOnly = true;
    cue =
        'TURN CONTRACT: Tool work is over. Give one short spoken wrap-up in '
        'the selected card’s diction now. No tool call, source dump, generic '
        '“Done”, or empty answer.';
  }

  void requestCheckInSpeech() {
    checkInWrapUp = true;
    speechOnly = true;
    cue = kWaifuCheckInTurnCue;
  }

  void requestVerify() {
    verifyCorrectionAttempts++;
    speechOnly = false;
    cue =
        'TURN CONTRACT: A project file changed. Re-read a touched path or '
        'run a project test/analyze command before claiming this done. '
        'Personality without that verify is not completion.';
  }

  String failureLine(String body) {
    if (todoWriteRequired && !todoWriteSucceeded) {
      return 'I did not actually update the todo list, so I stopped instead of '
          'pretending I did.';
    }
    if (mutationRequired && !mutationSucceeded) {
      if (mode == WaifuMode.plan) {
        return 'I could not write a plan file under $kWaifuPlansDir, so I '
            'stopped instead of pretending I planned.';
      }
      return 'I could not put a real change on disk, so I stopped instead of '
          'pretending I did.';
    }
    if (enforceVerify && verifyRequired && !verified) {
      return 'I put a change on disk but did not re-read or test it, so I '
          'stopped instead of pretending the work was done.';
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
