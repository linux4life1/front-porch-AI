// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Regenerates test/fixtures/growth/milestone_burst_vectors.json from the Dart
// sim. Run only when the celebration is meant to change, then make the web
// twin match (its vitest reads the same file):
//
//   dart run tool/gen_milestone_burst_vectors.dart

import 'dart:convert';
import 'dart:io';

import 'package:front_porch_ai/services/chat/milestone_burst.dart';

const _frames = [0, 15, 30, 60, 110];
const _sampled = 6;

void main() {
  const momentId = 'moment-vector-1';
  final seeds = [7, burstSeedFor(momentId)];
  final runs = <Map<String, dynamic>>[];
  for (final kind in BurstKind.values) {
    for (final seed in seeds) {
      final burst = MilestoneBurst.plan(kind, seed);
      final frames = <Map<String, dynamic>>[];
      for (final f in _frames) {
        burst.stepTo(f);
        frames.add({
          'frame': f,
          'alphaSum': burst.particles.fold<double>(0, (s, p) => s + p.alpha),
          'particles': [
            for (final p in burst.particles.take(_sampled))
              {
                'shape': p.shape.name,
                'color': p.color,
                'x': p.x,
                'y': p.y,
                'size': p.size,
                'rot': p.rot,
                'alpha': p.alpha,
              },
          ],
        });
      }
      runs.add({
        'kind': kind.name,
        'seed': seed,
        'count': burst.particles.length,
        'duration': burst.duration,
        'frames': frames,
      });
    }
  }
  final out = File('test/fixtures/growth/milestone_burst_vectors.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'dt': kBurstDt, 'momentId': momentId, 'momentSeed': burstSeedFor(momentId), 'runs': runs})}\n',
    );
  stdout.writeln('wrote ${out.path} (${runs.length} runs)');
}
