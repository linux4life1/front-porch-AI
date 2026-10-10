// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The phone's chat header, side portrait and group tiles skip the flat
// coloured picture a character made without a portrait carries. They learn
// it from the relay: `placeholderPortrait` on each chat-state cast entry and
// on each /api/groups member (additive; `hasAvatar` keeps its meaning).
// Real ChatFacade / GroupFacade over a real ChatService, store and files.
// The relay never waits on a probe: the first answer counts the picture as
// real, the background probe then asks the phone to refetch once.
// Phone twins: web_ui/src/pages/chatPlaceholderPortrait.test.tsx,
// web_ui/src/components/library/GroupCard.placeholder.test.tsx.

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/web/facade/chat_facade.dart';
import 'package:front_porch_ai/services/web/facade/group_facade.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';

import '../../helpers/reprocess_needs_harness.dart';

/// Records what the relay pushes to the phones.
class _RecordingHub extends StreamHub {
  _RecordingHub() : super(const Stream<String>.empty(), () => false);

  final pushed = <Map<String, dynamic>>[];

  @override
  void broadcast(Map<String, dynamic> event) => pushed.add(event);
}

File _realPortrait400x600(String path) {
  final photo = img.decodeImage(
    File('assets/backgrounds/beach.png').readAsBytesSync(),
  )!;
  final square = img.copyResizeCropSquare(photo, size: 600);
  final cropped = img.copyCrop(square, x: 100, y: 0, width: 400, height: 600);
  return File(path)..writeAsBytesSync(img.encodePng(cropped));
}

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 500 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue, reason: 'the background probe never reported');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupReprocessPathProviderMock();

  late ReprocessHarness h;
  late _RecordingHub hub;
  late ChatFacade facade;

  setUp(() async {
    PlaceholderPortraitProbe.clearCache();
    h = ReprocessHarness();
    await h.boot();
    hub = _RecordingHub();
    facade = ChatFacade(h.chat, h.repo, null, hub, null);
  });
  tearDown(() => h.dispose());

  Future<File> placeholderAt(String path) async {
    await V2CardService().saveCardAsPng(
      CharacterCard(name: 'Juniper'),
      path,
      null,
    );
    return File(path);
  }

  List<Map<String, dynamic>> cast() =>
      (facade.state()['cast'] as List).cast<Map<String, dynamic>>();

  int chatUpdates() =>
      hub.pushed.where((e) => e['event'] == 'chat_updated').length;

  test(
    'a 1:1 host with only the placeholder is marked, after one push',
    () async {
      final dir = h.storage.charactersDir..createSync(recursive: true);
      final file = await placeholderAt(p.join(dir.path, 'Juniper_1.png'));
      await h.chat.setActiveCharacter(
        needsCard('Juniper')..imagePath = file.path,
      );
      await h.settleTurn();
      hub.pushed.clear();

      // Cold: answered at once, the unknown picture counted as real.
      expect(cast().single['placeholderPortrait'], isFalse);
      // The background probe finds the placeholder and asks for a refetch.
      await _until(() => chatUpdates() > 0);
      final warm = cast().single;
      expect(warm['placeholderPortrait'], isTrue);
      expect(warm['hasAvatar'], isTrue);
      // Known now: no further pushes.
      cast();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(chatUpdates(), 1);
    },
  );

  test('a real 1:1 portrait is never marked and pushes nothing', () async {
    final dir = h.storage.charactersDir..createSync(recursive: true);
    final file = _realPortrait400x600(p.join(dir.path, 'Marlow_1.png'));
    await h.chat.setActiveCharacter(needsCard('Marlow')..imagePath = file.path);
    await h.settleTurn();
    hub.pushed.clear();

    expect(cast().single['placeholderPortrait'], isFalse);
    await PlaceholderPortraitProbe.check(file, version: h.repo.coverEpoch);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(cast().single['placeholderPortrait'], isFalse);
    expect(chatUpdates(), 0);
  });

  test('group members: the chat cast and the library tile', () async {
    final avatars = Directory(
      p.join(h.storage.groupsDir.path, 'pp-grp', 'avatars'),
    )..createSync(recursive: true);
    await placeholderAt(p.join(avatars.path, 'juniper.png'));
    _realPortrait400x600(p.join(avatars.path, 'marlow.png'));
    await h.db.insertGroup(GroupsCompanion.insert(id: 'pp-grp', name: 'Porch'));
    for (final (id, name) in [('pp-a', 'Juniper'), ('pp-b', 'Marlow')]) {
      await h.db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: id,
          groupId: 'pp-grp',
          name: name,
          firstMessage: const Value('Evening.'),
          avatarFilename: Value('${name.toLowerCase()}.png'),
        ),
      );
    }
    final groups = GroupChatRepository(h.storage, h.db);
    await groups.reload();
    await h.chat.setActiveGroup(
      GroupChat(id: 'pp-grp', name: 'Porch'),
      groupRepo: groups,
    );
    await h.settleTurn();
    hub.pushed.clear();

    // The chat state's cast.
    bool marked(String name) =>
        cast().firstWhere((c) => c['name'] == name)['placeholderPortrait']
            as bool;
    expect(marked('Juniper'), isFalse);
    await _until(() => chatUpdates() > 0);
    expect(marked('Juniper'), isTrue);
    expect(marked('Marlow'), isFalse);

    // The library's group tile (/api/groups).
    final library = GroupFacade(groups, h.storage, h.repo, h.db);
    var refetches = 0;
    library.onPlaceholderPortraitsFound = () => refetches++;
    Future<Map<String, bool>> members() async {
      final group = (await library.list()).firstWhere(
        (g) => g['id'] == 'pp-grp',
      );
      return {
        for (final m in (group['members'] as List).cast<Map>())
          m['name'] as String: m['placeholderPortrait'] as bool,
      };
    }

    expect(await members(), {'Juniper': false, 'Marlow': false});
    await _until(() => refetches > 0);
    expect(await members(), {'Juniper': true, 'Marlow': false});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(refetches, 1);
  });
}
