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

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/engine_health.dart';

void main() {
  final health = EngineHealth.instance;

  setUp(health.resetForTest);
  tearDown(health.resetForTest);

  test('all engines listed in stable order, idle by default', () {
    final names = health.entries.map((e) => e.name).toList();
    expect(names, [
      EngineHealth.expressions,
      EngineHealth.kokoro,
      EngineHealth.piper,
      EngineHealth.whisper,
      EngineHealth.drawThings,
      EngineHealth.embeddings,
    ]);
    for (final e in health.entries) {
      expect(e.nativeCount, 0);
      expect(e.failureCount, 0);
    }
  });

  test('reportNative and reportFailure tally per engine', () {
    health.reportNative(EngineHealth.kokoro);
    health.reportNative(EngineHealth.kokoro);
    health.reportFailure(EngineHealth.whisper, 'transcription failed: boom');

    final kokoro = health.entries.firstWhere(
      (e) => e.name == EngineHealth.kokoro,
    );
    final whisper = health.entries.firstWhere(
      (e) => e.name == EngineHealth.whisper,
    );
    expect(kokoro.nativeCount, 2);
    expect(kokoro.failureCount, 0);
    expect(whisper.failureCount, 1);
    expect(whisper.lastFailureReason, 'transcription failed: boom');
  });

  test('unknown engine names are ignored, not crashed on', () {
    health.reportNative('No Such Engine');
    health.reportFailure('No Such Engine', 'whatever');
    expect(health.entries.every((e) => e.failureCount == 0), isTrue);
  });

  test('onFirstFailure fires exactly once per engine per session', () {
    final fired = <String>[];
    health.onFirstFailure = (engine, reason) => fired.add('$engine|$reason');

    health.reportFailure(EngineHealth.piper, 'first');
    health.reportFailure(EngineHealth.piper, 'second');
    health.reportFailure(EngineHealth.expressions, 'model missing');

    expect(fired, [
      '${EngineHealth.piper}|first',
      '${EngineHealth.expressions}|model missing',
    ]);
  });

  test('expected failures are tallied but never fire the notice', () {
    final fired = <String>[];
    health.onFirstFailure = (engine, reason) => fired.add(engine);

    health.reportFailure(
      EngineHealth.whisper,
      'model missing after download attempt',
      expected: true,
    );
    health.reportFailure(
      EngineHealth.piper,
      'no sherpa export (custom voice)',
      expected: true,
    );
    expect(fired, isEmpty);
    final whisper = health.entries.firstWhere(
      (e) => e.name == EngineHealth.whisper,
    );
    expect(whisper.failureCount, 1);

    // A real failure on the same engine still notices afterwards.
    health.reportFailure(EngineHealth.whisper, 'engine crashed');
    expect(fired, [EngineHealth.whisper]);
    expect(whisper.failureCount, 2);
  });

  test('buildReport marks unused engines and carries failure reasons', () {
    health.reportNative(EngineHealth.kokoro);
    health.reportFailure(EngineHealth.whisper, 'unsupported audio format');
    final report = health.buildReport();
    expect(report, contains('${EngineHealth.expressions}: not used'));
    expect(report, contains('${EngineHealth.kokoro}: ok ×1, failed ×0'));
    expect(report, contains('unsupported audio format'));
  });
}
