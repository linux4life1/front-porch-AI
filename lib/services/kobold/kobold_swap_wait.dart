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

/// Why a swap did not finish.
class KoboldSwapTimeout implements Exception {
  const KoboldSwapTimeout({required this.restarted, required this.waited});

  /// False: the engine never started a new model process, so the request
  /// was not acted on. True: it restarted and the model did not become
  /// ready in time.
  final bool restarted;
  final Duration waited;

  @override
  String toString() => restarted
      ? 'KoboldCpp did not finish loading within ${waited.inSeconds}s'
      : 'KoboldCpp did not act on the reload within ${waited.inSeconds}s';
}

/// A reload KoboldCpp answered but did not load: it went back to the config
/// it was started with.
class KoboldSwapFailed implements Exception {
  const KoboldSwapFailed(this.message);

  final String message;

  @override
  String toString() => message;
}

/// How long a model file of [sizeBytes] may take to load before the app
/// gives up: a minute, plus eight seconds for every gigabyte (a slow disk
/// reads about that much), capped at fifteen minutes.
Duration koboldLoadTimeout(int sizeBytes) {
  final gigabytes = sizeBytes / (1024 * 1024 * 1024);
  return Duration(seconds: (60 + 8 * gigabytes).round().clamp(60, 900));
}

/// Whether an engine reporting [uptimeSeconds], asked [sinceRequest] ago to
/// reload, is the NEW model process.
///
/// KoboldCpp answers a reload at once and acts on it up to a second later,
/// so the old process keeps answering for a while. Its uptime is at least
/// the time since the request. The new process is started no sooner than
/// half a second after the request, so its uptime is at least that much
/// less.
bool koboldIsNewProcess(double uptimeSeconds, Duration sinceRequest) =>
    uptimeSeconds < sinceRequest.inMilliseconds / 1000 - 0.25;

/// How often [waitForKoboldReload] asks the engine.
const Duration _pollEvery = Duration(milliseconds: 150);

/// Waits for a reload that was just asked for to really take effect: first
/// for the engine to start a new model process ([uptime], null while
/// nothing answers), then for [ready]. "The request returned" and "the
/// server answers" mean neither.
///
/// Throws [KoboldSwapTimeout] after [timeout].
Future<void> waitForKoboldReload({
  required Future<double?> Function() uptime,
  required Future<bool> Function() ready,
  required Duration timeout,
  DateTime Function() now = DateTime.now,
  Future<void> Function(Duration)? pause,
}) async {
  final asked = now();
  final wait = pause ?? (d) => Future<void>.delayed(d);
  var restarted = false;
  while (true) {
    final since = now().difference(asked);
    if (!restarted) {
      final up = await uptime();
      restarted = up != null && koboldIsNewProcess(up, now().difference(asked));
    }
    if (restarted && await ready()) return;
    if (since >= timeout) {
      throw KoboldSwapTimeout(restarted: restarted, waited: since);
    }
    await wait(_pollEvery);
  }
}
