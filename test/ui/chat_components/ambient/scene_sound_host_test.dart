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

// The scene sound as the chat page mounts it (docs/design/ambient-stage.md
// §5): the host around a real Ambient Stage plays the storm's loop, the
// stage's own flash brings thunder after its gap, Scene sound off never
// makes a player, a minimised window holds the loop, and unmounting (the
// chat closing) frees the players. The players are a fake.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:front_porch_ai/services/chat/scene/scene_effects.dart';
import 'package:front_porch_ai/services/chat/scene/scene_sound_service.dart';
import 'package:front_porch_ai/services/chat/scene/scene_tokens.dart';
import 'package:front_porch_ai/services/chat/weather_engine.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/ambient_stage.dart';
import 'package:front_porch_ai/ui/chat_components/ambient/scene_sound_host.dart';

class _FakeOutput implements SceneSoundOutput {
  final List<String> calls = [];
  String? looping;
  bool disposed = false;

  @override
  Future<void> loop(String? asset, double volume) async {
    looping = asset;
    calls.add('loop ${asset ?? '-'}');
  }

  @override
  Future<void> setLoopVolume(double volume) async {}

  @override
  Future<void> pauseLoop() async => calls.add('pause');

  @override
  Future<void> resumeLoop() async => calls.add('resume');

  @override
  Future<void> oneShot(String asset, double volume) async =>
      calls.add('shot $asset');

  @override
  Future<void> dispose() async => disposed = true;
}

SceneTokens _storm() => SceneSim.resolve(
  daypart: 'night',
  condition: WeatherCondition.storm,
  temp: TempBand.cool,
  dark: true,
  level: SceneLevel.effects,
  seed: 4242,
);

Widget _host({
  required bool enabled,
  required _FakeOutput out,
  required void Function() made,
}) => MaterialApp(
  home: MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: Scaffold(
      body: SceneSoundHost(
        tokens: _storm(),
        enabled: enabled,
        volume: 0.5,
        output: () {
          made();
          return out;
        },
        builder: (context, onFlash) =>
            AmbientStage(tokens: _storm(), animated: true, onFlash: onFlash),
      ),
    ),
  ),
);

void main() {
  testWidgets('a storm plays its loop and the stage\'s flash brings thunder', (
    tester,
  ) async {
    final out = _FakeOutput();
    await tester.pumpWidget(_host(enabled: true, out: out, made: () {}));
    await tester.pump(const Duration(milliseconds: 50));
    expect(out.looping, 'audio/scene/storm_rain.mp3');

    // The stage's sim flashes 2.5 to 8.5 s in, the rumble follows within
    // 1.8 s; frames step the sim at most 0.1 s each.
    for (
      var i = 0;
      i < 110 && !out.calls.any((c) => c.startsWith('shot'));
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final shots = out.calls.where((c) => c.startsWith('shot')).toList();
    expect(shots, isNotEmpty, reason: 'thunder after the flash');
    expect(
      shots.first,
      matches(RegExp(r'^shot audio/scene/thunder_[123]\.mp3$')),
    );

    // Minimised: the loop holds; restored, it carries on.
    final window = tester.state(find.byType(SceneSoundHost)) as WindowListener;
    window.onWindowMinimize();
    expect(out.calls.last, 'pause');
    window.onWindowRestore();
    expect(out.calls.last, 'resume');

    // The chat closes: the players go.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(out.disposed, isTrue);
  });

  testWidgets('Scene sound off never makes a player', (tester) async {
    final out = _FakeOutput();
    var made = 0;
    await tester.pumpWidget(
      _host(enabled: false, out: out, made: () => made++),
    );
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(made, 0);
    expect(out.calls, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
