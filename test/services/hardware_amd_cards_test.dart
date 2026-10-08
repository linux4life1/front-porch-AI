// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The AMD driver lists each graphics card twice under /sys/class/drm: as
// `cardN` and as its `renderDN` node, both with the card's memory files
// (seen on a real RX 6900 XT: card0 and renderD128, the same PCI device,
// 16,368 MB each). A card counts once. The tree here has that layout.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/services/services.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai drm');
  });

  tearDown(() => root.delete(recursive: true));

  const mib = 1024 * 1024;

  Future<void> node(String name, {int? totalMb, int? usedMb}) async {
    final device = Directory(p.join(root.path, name, 'device'));
    await device.create(recursive: true);
    if (totalMb != null) {
      await File(
        p.join(device.path, 'mem_info_vram_total'),
      ).writeAsString('${totalMb * mib}\n');
    }
    if (usedMb != null) {
      await File(
        p.join(device.path, 'mem_info_vram_used'),
      ).writeAsString('${usedMb * mib}\n');
    }
  }

  test('one card, listed as card0 and renderD128, counts once', () async {
    await node('card0', totalMb: 16368, usedMb: 1200);
    await node('renderD128', totalMb: 16368, usedMb: 1200);
    await Directory(p.join(root.path, 'card0-DP-1')).create();

    final cards = await amdDrmCards(root.path);

    expect([for (final c in cards) c.id], [0]);
    expect(cards.single.total, '${16368 * mib}');
    expect(cards.single.used, '${1200 * mib}');
  });

  test('two cards come back in card order, each once', () async {
    await node('card1', totalMb: 8176);
    await node('renderD129', totalMb: 8176);
    await node('card0', totalMb: 16368, usedMb: 100);
    await node('renderD128', totalMb: 16368, usedMb: 100);

    final cards = await amdDrmCards(root.path);

    expect([for (final c in cards) c.id], [0, 1]);
    expect(cards[1].used, isNull, reason: 'no used-memory file for card1');
  });

  test('no driver folder means no cards', () async {
    expect(await amdDrmCards(p.join(root.path, 'missing')), isEmpty);
  });
}
