// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// One rule for how many chats the slot keeper keeps: the open chat, and the
// recent ones Settings → Advanced asks for (none by default), never more
// than the free memory and KoboldCpp's five save slots have room for. The
// keeper counts with it, and so does what the Local model card says about
// going back to another chat. The card is worked out for a real model header
// (Qwen3-14B, grown to its real size) on a machine with room for five.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/hardware_info.dart';
import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/utils/utils.dart';

import '../kobold_service_test.dart'
    show createStorageService, setupPathProviderMock;

const _fixtures = 'test/fixtures/gguf_headers';
const _quick = 'Going back to another chat is quick.';
const _moment = 'Going back to another chat takes a moment to catch up.';

({GGUFModelInfo info, int bytes}) _header(String name) {
  final side =
      (jsonDecode(File('$_fixtures/$name.json').readAsStringSync()) as Map)
          .cast<String, dynamic>();
  final bytes = side['fixture_file_bytes'] as int;
  final header = GGUFFileReader.parseHeaderBytes(
    File('$_fixtures/$name.gguf').readAsBytesSync(),
  )!;
  return (
    info: GGUFParser.modelInfoFromHeader(header, fileSize: bytes)!,
    bytes: bytes,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupPathProviderMock();

  group('the rule', () {
    test('by default only the open chat, whatever the room', () {
      for (final room in [1, 2, 5]) {
        expect(koboldKeeperChats(recent: 0, room: room), 1, reason: '$room');
      }
    });

    test('recent chats on top, never past the room', () {
      expect(koboldKeeperChats(recent: 2, room: 5), 3);
      expect(koboldKeeperChats(recent: 4, room: 5), 5);
      expect(koboldKeeperChats(recent: 4, room: 2), 2);
      expect(koboldKeeperChats(recent: 3, room: 0), 0);
    });

    test(
      "the room is KoboldCpp's five at most, fewer when memory is short",
      () {
        const plenty = (slotMb: 1000, freeRamMb: 64000, modelRamMb: 8000);
        const short = (slotMb: 1000, freeRamMb: 12100, modelRamMb: 8000);
        expect(koboldKeeperRoom(plenty), kKoboldSaveSlots);
        expect(koboldKeeperRoom(short), 2);
        expect(
          koboldKeeperChats(recent: 0, room: koboldKeeperRoom(plenty)),
          1,
          reason: 'room for five still keeps only the open chat by default',
        );
      },
    );

    test('Settings offers none to four recent chats: the open one and four '
        "fill KoboldCpp's five", () {
      expect(kKoboldKeepRecentChoices, [0, 1, 2, 3, 4]);
      expect(kKoboldKeepRecentChoices.last + 1, kKoboldSaveSlots);
      expect(kKoboldKeepRecentChoices.map(koboldKeepRecentLabel), [
        'Off',
        '1',
        '2',
        '3',
        '4',
      ]);
    });
  });

  group('the Local model card follows the same rule', () {
    late StorageService storage;

    setUp(() async => storage = await createStorageService());

    Future<List<String>> lines({required int systemMb}) async {
      final m = _header('Qwen3-14B');
      return KoboldStatusFacts.of(
        storage: storage,
        hardware: HardwareInfo(
          gpuName: 'NVIDIA GeForce RTX 4080',
          vramMb: 16384,
          ramMb: 65536,
          vendor: 'Nvidia',
          hasCuda: true,
        ),
        free: (graphics: 16000, system: systemMb),
        info: m.info,
        bytes: m.bytes,
      )!.lines;
    }

    test('by default going back to another chat takes a moment, even with '
        'room for five', () async {
      expect(await lines(systemMb: 60000), contains(_moment));
    });

    test('with recent chats kept in Advanced it is quick', () async {
      await storage.backendSettings.setKeepRecentChats(1);
      expect(await lines(systemMb: 60000), contains(_quick));
    });

    test(
      'asked for, but memory has room for only the open chat: a moment',
      () async {
        await storage.backendSettings.setKeepRecentChats(4);
        // A full context of this model is 2,560 MB, its own share 511 MB, and
        // 2,048 are set aside: room for one.
        expect(await lines(systemMb: 5200), contains(_moment));
      },
    );
  });
}
