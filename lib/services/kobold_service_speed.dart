// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// What the speed test reads from the engine: its own speed line for each
// timing prompt, and how long each model took to load.

part of 'kobold_service.dart';

/// Kept beside the service, like [_RequestState]: test fakes implement
/// [KoboldService] and still reach the extensions.
class _SpeedState {
  final KoboldSpeedLines lines = KoboldSpeedLines();
  final KoboldLoadClock loads = KoboldLoadClock();
}

final Expando<_SpeedState> _speedStates = Expando('fpai.koboldSpeed');

extension KoboldServiceSpeed on KoboldService {
  _SpeedState get _speed => _speedStates[this] ??= _SpeedState();

  /// One timing prompt for the speed test: a fresh prompt of about 2,000
  /// tokens that writes [kKoboldTimingWrite], in the line like any request,
  /// and how fast the engine says it read and wrote it. Null when the engine
  /// printed no speed for it in time.
  Future<KoboldSpeed?> _timeTurn(int round) => _runSerialized(() async {
    final mark = _speed.lines.seen;
    await timeKoboldPrompt(
      _baseUrl,
      round,
      write: kKoboldTimingWrite,
      fullLength: true,
    );
    return _speed.lines.after(mark);
  });

  /// How long the latest load of [model] took, when one was seen.
  Duration? loadTookFor(String model) => _speed.loads.lastFor(model);

  /// The newest speeds the engine printed, for an estimate before anything
  /// is timed.
  KoboldSpeed? get lastSpeed => _speed.lines.last;
}
