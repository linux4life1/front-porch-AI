// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Free memory read from what each system's tools really print.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/free_memory_parsers.dart';

void main() {
  test('nvidia-smi: the chosen card, else the one with the most free', () {
    expect(nvidiaFreeMb('5222\n'), 5222);
    expect(nvidiaFreeMb('1200\n7900\n'), 7900);
    expect(nvidiaFreeMb('1200\n7900\n', gpuId: 0), 1200);
    expect(nvidiaFreeMb('5222 MiB\n'), 5222, reason: 'units left on');
    expect(nvidiaFreeMb('No devices were found\n'), isNull);
  });

  test('/proc/meminfo: MemAvailable', () {
    const text =
        'MemTotal:       32768000 kB\n'
        'MemFree:         1024000 kB\n'
        'MemAvailable:   20480000 kB\n';
    expect(meminfoAvailableMb(text), 20000);
    expect(meminfoAvailableMb('MemTotal: 1 kB\n'), isNull);
  });

  test('vm_stat (macOS): free, inactive, speculative and purgeable pages', () {
    // As this Mac printed it (16 KB pages).
    const text =
        'Mach Virtual Memory Statistics: (page size of 16384 bytes)\n'
        'Pages free:                                  5635977.\n'
        'Pages active:                                1014036.\n'
        'Pages inactive:                              1213251.\n'
        'Pages speculative:                            106531.\n'
        'Pages throttled:                                   0.\n'
        'Pages wired down:                             312038.\n'
        'Pages purgeable:                               33364.\n';
    expect(
      vmStatAvailableMb(text),
      (5635977 + 1213251 + 106531 + 33364) * 16384 ~/ (1024 * 1024),
    );
    expect(vmStatAvailableMb('no header'), isNull);
  });

  test('an AMD card on Linux: total less used', () {
    expect(
      amdFreeMb(totalBytes: '17163091968\n', usedBytes: '37748736\n'),
      16332,
    );
    expect(amdFreeMb(totalBytes: 'x', usedBytes: '1'), isNull);
  });

  test('two AMD cards: the chosen one, else the one with the most free', () {
    expect(amdChosenFreeMb([1200, 15800], gpuId: 0), 1200);
    expect(amdChosenFreeMb([1200, 15800], gpuId: 1), 15800);
    expect(amdChosenFreeMb([1200, 15800]), 15800);
    // An unreadable card keeps its place: card 2 is still card 2.
    expect(amdChosenFreeMb([1200, null, 900], gpuId: 2), 900);
    expect(amdChosenFreeMb([1200, null, 15800], gpuId: 1), 15800);
    expect(amdChosenFreeMb([]), isNull);
  });

  test('Windows: FreePhysicalMemory in kB', () {
    expect(windowsFreeMb('11328512\r\n'), 11063);
    expect(windowsFreeMb(''), isNull);
  });
}
