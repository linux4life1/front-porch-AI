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

/// Whether a config runs flash attention: KoboldCpp has it on unless the
/// config turns it off, by `noflashattention: true` or, in a file from
/// before that name, `flashattention: false` (read as the preset reader
/// reads it).
bool kcppsRunsFlashAttention(Map<dynamic, dynamic> config) =>
    config.containsKey('noflashattention')
    ? config['noflashattention'] != true
    : config['flashattention'] != false;

/// Whether [output] from the engine says a reply was finished.
bool koboldReplyFinishedIn(String output) => _done.hasMatch(output);

/// The engine's output put back into lines across reads: a pipe hands it
/// over in pieces, and a line can arrive in two of them.
class KoboldOutputLines {
  String _pending = '';

  /// The lines [chunk] completes, then the line still being written, as it
  /// stands: KoboldCpp ends a reply's last line only when it next prints.
  List<String> add(String chunk) {
    final lines = (_pending + chunk).split(RegExp(r'\r\n|\r|\n'));
    _pending = lines.removeLast();
    // A line with no end in sight keeps only its last part.
    if (_pending.length > 4096) {
      _pending = _pending.substring(_pending.length - 4096);
    }
    return [...lines, if (_pending.isNotEmpty) _pending];
  }
}

/// Whether to start again with flash attention off: the ROCm build died
/// mid-answer with it on, on its first reply ([replyFinished]: no reply has
/// finished since this KoboldCpp process started), and this machine has not
/// been marked yet. A crash after a reply worked is something else and
/// only stops, with its reason. Running out of memory is not this either:
/// flash attention uses less.
bool koboldRetryWithoutFlashAttention({
  required KoboldFailure failure,
  required bool rocmWithFlashAttention,
  required bool alreadyMarked,
  bool replyFinished = false,
}) =>
    failure.kind == KoboldFailureKind.diedWhileAnswering &&
    rocmWithFlashAttention &&
    !alreadyMarked &&
    !replyFinished;
