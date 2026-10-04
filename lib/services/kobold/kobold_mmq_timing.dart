// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Which is faster on this card, MMQ on or off. KoboldCpp turns it on; on
// the original author's GTX 1060 it was slower (761.63 against 988.62
// tokens a second reading a prompt). The editor times both on request; auto
// mode learns it from the speeds KoboldCpp prints after each reply.

import 'dart:convert';
import 'dart:io';

/// One reply's speeds, as KoboldCpp prints them: "Processed:2181 in 0.68s
/// (3212.08T/s), Generated:32/32 in 0.38s (83.33T/s)".
typedef KoboldSpeed = ({
  int read,
  double readSeconds,
  int written,
  double writeSeconds,
});

final RegExp _speedLine = RegExp(
  r'Processed:(\d+) in ([\d.]+)s \([\d.]+T/s\), '
  r'Generated:(\d+)/\d+ in ([\d.]+)s',
);

/// The speeds in a KoboldCpp log line; null for any other line.
KoboldSpeed? parseKoboldSpeed(String line) {
  final m = _speedLine.firstMatch(line);
  if (m == null) return null;
  return (
    read: int.parse(m.group(1)!),
    readSeconds: double.parse(m.group(2)!),
    written: int.parse(m.group(3)!),
    writeSeconds: double.parse(m.group(4)!),
  );
}

/// Seconds for a typical turn at these speeds: reading 1,000 tokens of
/// prompt and writing 200. Only replies that read and wrote enough to time
/// count; the middle of what is left is taken, so one slow reply (the
/// first after a load, read from the disk) does not decide. Null with
/// fewer than three such replies.
double? koboldTurnSeconds(List<KoboldSpeed> replies) {
  final read = [
    for (final r in replies)
      if (r.read >= 512 && r.readSeconds > 0) r.read / r.readSeconds,
  ]..sort();
  final write = [
    for (final r in replies)
      if (r.written >= 16 && r.writeSeconds > 0) r.written / r.writeSeconds,
  ]..sort();
  if (read.length < 3 || write.length < 3) return null;
  return 1000 / read[read.length ~/ 2] + 200 / write[write.length ~/ 2];
}

/// MMQ on (true) or off when both have been timed; null until then.
bool? koboldMmqFaster({
  required List<KoboldSpeed> on,
  required List<KoboldSpeed> off,
}) {
  final a = koboldTurnSeconds(on);
  final b = koboldTurnSeconds(off);
  if (a == null || b == null) return null;
  return a <= b;
}

/// A prompt of about 2,000 tokens that no earlier one starts with, so
/// KoboldCpp reads all of it.
String koboldTimingPrompt(int round) {
  const lines = [
    'The porch light flickered as the evening storm rolled in from the hills.',
    'Old Mrs. Hale counted the jars of peaches on the pantry shelf again.',
    'A dog barked twice down the lane and then thought better of it.',
    'Somebody had left a fiddle on the swing, its strings loose with damp.',
    'The radio on the sill played a song nobody had asked for in years.',
    'Wind pushed the screen door open and let it bang against the frame.',
    'Corn stood high in the field beyond the fence, rustling like paper.',
    'A pickup rattled by with a load of hay and a boy asleep on top.',
  ];
  final out = StringBuffer(
    'Timing run $round, ${DateTime.now().microsecondsSinceEpoch}.\n',
  );
  for (var i = 0; i < 26; i++) {
    for (final line in lines) {
      out.write('${i + 1}. $line ');
    }
    out.write('\n');
  }
  out.write('\nWhat happened next on the porch? Answer in two sentences.\n');
  return out.toString();
}

/// Times one fresh prompt and a short reply on the engine at [baseUrl].
Future<Duration> timeKoboldPrompt(String baseUrl, int round) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final watch = Stopwatch()..start();
  try {
    final request = await client.postUrl(Uri.parse('$baseUrl/api/v1/generate'));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'prompt': koboldTimingPrompt(round),
        'max_length': 48,
        'temperature': 0.7,
        'quiet': true,
      }),
    );
    final response = await request.close().timeout(const Duration(minutes: 15));
    await response.drain<void>();
    if (response.statusCode != 200) {
      throw HttpException('KoboldCpp answered ${response.statusCode}');
    }
    return watch.elapsed;
  } finally {
    client.close(force: true);
  }
}
