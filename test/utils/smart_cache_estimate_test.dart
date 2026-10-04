// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// Smart cache slots against what a real KoboldCpp printed ("KV Save State
// N: Created SaveState of T tokens, costing M MB", rounded down) and what
// its source does with the number a preset asks for.
//
//  - Qwen3-14B and Qwen3-30B-A3B: KoboldCpp 1.122.1, Vulkan, a 2,388-token
//    chat saved to a slot: 372 and 223 MB.
//  - Qwen3.6-35B-A3B (hybrid): the original author's log, CUDA, smart cache
//    2: "Prepared 3 KV slots"; 63 MB at 54 tokens, 67 at 244, 68 at 275.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/utils/gguf_parser.dart';
import 'package:front_porch_ai/utils/gguf_reader.dart';
import 'package:front_porch_ai/utils/smart_cache_estimate.dart';

const _dir = 'test/fixtures/gguf_headers';

GGUFModelInfo _info(String name) {
  final side = (jsonDecode(File('$_dir/$name.json').readAsStringSync()) as Map)
      .cast<String, dynamic>();
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_dir/$name.gguf').readAsBytesSync(),
  )!;
  return GGUFParser.modelInfoFromHeader(
    header,
    fileSize: side['fixture_file_bytes'] as int,
  )!;
}

/// The engine's figure rounded down; the estimate at or just above it.
Matcher _printed(int mb) => allOf(
  greaterThanOrEqualTo(mb * 1024 * 1024),
  lessThan((mb + 2) * 1024 * 1024),
);

void main() {
  test('a slot costs the cache rows of the chat it holds', () {
    expect(
      smartCacheSlotBytes(_info('Qwen3-14B'), tokens: 2388),
      _printed(372),
    );
    expect(
      smartCacheSlotBytes(_info('Qwen3-30B-A3B'), tokens: 2388),
      _printed(223),
    );
  });

  test('a hybrid model\'s slot also holds its recurrent state', () {
    final hybrid = _info('Qwen3.6-35B-A3B-Q4_K_XL');
    expect(smartCacheSlotBytes(hybrid, tokens: 54), _printed(63));
    expect(smartCacheSlotBytes(hybrid, tokens: 244), _printed(67));
    expect(smartCacheSlotBytes(hybrid, tokens: 275), _printed(68));
  });

  test('the most a slot takes is a chat that fills the context', () {
    // 2600.00 MiB of cache at 16k on the real engine (16,640 cells), of
    // which a 16,384-token chat fills 16,384.
    expect(smartCacheSlotMb(_info('Qwen3-14B'), contextSize: 16384), 2560);
    // An 8-bit cache stores 8.5 bits a value.
    expect(
      smartCacheSlotMb(
        _info('Qwen3-14B'),
        contextSize: 16384,
        sizeFactor: 0.53125,
      ),
      1360,
    );
  });

  group('the slots KoboldCpp really makes', () {
    int slots(
      int asked, {
      bool recurrent = false,
      bool fastForward = true,
      bool contextShift = true,
    }) => koboldSmartCacheSlots(
      asked: asked,
      recurrent: recurrent,
      fastForward: fastForward,
      contextShift: contextShift,
    );

    test('a plain model gets what was asked; 1 means the default, 5', () {
      expect(slots(0), 0);
      expect(slots(1), 5);
      expect(slots(3), 3);
    });

    test('a hybrid model with context shift on always gets smart cache, '
        'with extra slots', () {
      expect(slots(2, recurrent: true), 3, reason: 'the author\'s log');
      expect(slots(0, recurrent: true), 7);
      expect(slots(5, recurrent: true), 7);
      expect(slots(0, recurrent: true, contextShift: false), 0);
    });

    test('without fast forward there is no smart cache', () {
      expect(slots(5, fastForward: false), 0);
      expect(slots(2, recurrent: true, fastForward: false), 0);
    });
  });

  group('the suggested number of slots', () {
    test('one per kind of prompt when memory allows', () {
      final s = suggestSmartCacheSlots(
        promptKinds: 3,
        slotMb: 400,
        freeRamMb: 64000,
        modelRamMb: 2000,
      );
      expect(s.slots, 3);
      expect(s.limit, SmartCacheLimit.promptKinds);
    });

    test('fewer when the free memory runs out', () {
      final s = suggestSmartCacheSlots(
        promptKinds: 4,
        slotMb: 2600,
        freeRamMb: 12000,
        modelRamMb: 3000,
      );
      expect(s.slots, 2);
      expect(s.limit, SmartCacheLimit.memory);
    });

    test('none on a machine the model already does not fit', () {
      // The author's machine: about 11 GB free, 17 GB of the model kept in
      // system memory.
      final s = suggestSmartCacheSlots(
        promptKinds: 3,
        slotMb: 383,
        freeRamMb: 11063,
        modelRamMb: 17274,
      );
      expect(s.slots, 0);
      expect(s.limit, SmartCacheLimit.noRoom);
    });

    test('a slot of unknown size is not suggested without room', () {
      final s = suggestSmartCacheSlots(
        promptKinds: 3,
        slotMb: 0,
        freeRamMb: 8000,
        modelRamMb: 9000,
      );
      expect(s.slots, 0);
    });
  });
}
