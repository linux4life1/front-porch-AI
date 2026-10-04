// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Why KoboldCpp stopped, in plain words, from what it printed and when.
// Only the cases seen on real engines are told apart; anything else says
// it stopped and points at the log.

/// What went wrong, as far as the engine's own output shows.
enum KoboldFailureKind {
  /// It said it ran out of memory.
  outOfMemory,

  /// It could not read the model file (exit code 2).
  unreadableModel,

  /// It stopped while answering, without saying why.
  diedWhileAnswering,

  /// It stopped for a reason the app cannot tell from its output.
  other,
}

class KoboldFailure {
  const KoboldFailure(this.kind, this.message);
  final KoboldFailureKind kind;

  /// What happened and what to try, for the user.
  final String message;
}

/// Out of memory, as the engine prints it. The ROCm build prints "ROCm
/// error: out of memory" (seen on an RX 6900 XT, on the first prompt after
/// a load that worked); the same code prints "CUDA" on NVIDIA.
final RegExp _outOfMemory = RegExp(
  r'(CUDA|ROCm|HIP) error: out of memory|out of memory|OutOfDeviceMemory',
  caseSensitive: false,
);

/// A line KoboldCpp prints while it reads a prompt or writes a reply, and
/// the line it prints when a reply is done.
final RegExp _working = RegExp(r'Processing Prompt|Generating \(');
final RegExp _done = RegExp(r'CtxLimit:\s*\d+');

/// Why the engine stopped. [log] is what it printed, oldest first;
/// [wasReady] says the model had loaded and answered the app's check.
KoboldFailure classifyKoboldExit({
  required List<String> log,
  required int? exitCode,
  required bool wasReady,
}) {
  final tail = log.length > 200 ? log.sublist(log.length - 200) : log;
  if (tail.any(_outOfMemory.hasMatch)) {
    return KoboldFailure(
      KoboldFailureKind.outOfMemory,
      wasReady
          ? 'KoboldCpp ran out of graphics memory while answering. Try a '
                'smaller context size, a smaller batch size, or a stronger '
                'cache compression.'
          : 'KoboldCpp ran out of graphics memory while loading the model. '
                'Try a smaller context size or a stronger cache compression.',
    );
  }
  if (!wasReady && exitCode == 2) {
    return const KoboldFailure(
      KoboldFailureKind.unreadableModel,
      'KoboldCpp could not read the model file.',
    );
  }
  if (wasReady && _answering(tail)) {
    return const KoboldFailure(
      KoboldFailureKind.diedWhileAnswering,
      'KoboldCpp stopped while answering, without saying why.',
    );
  }
  return KoboldFailure(
    KoboldFailureKind.other,
    wasReady
        ? 'KoboldCpp stopped (exit code $exitCode). The engine log says more.'
        : 'KoboldCpp stopped while loading the model (exit code $exitCode). '
              'The engine log says more.',
  );
}

/// True when the last thing the engine was doing was a prompt or a reply
/// it never finished.
bool _answering(List<String> log) {
  for (final line in log.reversed) {
    if (_done.hasMatch(line)) return false;
    if (_working.hasMatch(line)) return true;
  }
  return false;
}

/// Whether to start again with flash attention off: the ROCm build died
/// mid-answer with it on, and this machine has not been marked yet.
/// Running out of memory is not this: flash attention uses less.
bool koboldRetryWithoutFlashAttention({
  required KoboldFailure failure,
  required bool rocmWithFlashAttention,
  required bool alreadyMarked,
}) =>
    failure.kind == KoboldFailureKind.diedWhileAnswering &&
    rocmWithFlashAttention &&
    !alreadyMarked;
