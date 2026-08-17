// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Widget test that PUMPS the real StoopUploadPage Content step.
// A source grep is not proof: this must go red if the Comments switch is
// removed from the page, moved off the Adult switch, or defaults ON.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/providers/auth_state.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/pages/repository/repository.dart';

/// A 1×1 PNG. The pick grid renders `Image.file`.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

class _FakeCharacterRepository extends ChangeNotifier
    implements CharacterRepository {
  _FakeCharacterRepository(this._characters);
  final List<CharacterCard> _characters;

  @override
  List<CharacterCard> get characters => List.unmodifiable(_characters);
  @override
  bool get isLoading => false;
  @override
  int get coverEpoch => 0;
  @override
  Future<void> loadCharacters() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFolderService extends ChangeNotifier implements FolderService {
  @override
  List<CharacterFolder> get folders => const [];
  @override
  List<CharacterFolder> getSubfolders(String? parentId) => const [];
  @override
  CharacterFolder? getFolderForCharacter(String filename) => null;
  @override
  CharacterFolder? getFolderForGroup(String groupId) => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeGroupChatRepository extends ChangeNotifier
    implements GroupChatRepository {
  @override
  List<GroupChat> get groups => const [];
  @override
  Future<List<GroupMember>> getMembersForGroup(String groupId) async =>
      const [];
  @override
  Future<List<File>> getMemberAvatarFiles(String groupId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWorldRepository extends ChangeNotifier implements WorldRepository {
  @override
  List<World> get worlds => const [];
  @override
  List<World> get placeWorlds => const [];
  @override
  bool get isLoading => false;
  @override
  Map<String, dynamic> fpWorldJson(World world) => {
    'name': world.name,
    'description': world.description,
    'biome': const <String, dynamic>{},
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory tmp;
  late CharacterCard card;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('stoop_upload_content');
    File('${tmp.path}/clive.png').writeAsBytesSync(_pngBytes);
    card = CharacterCard(
      name: 'Clean Clive',
      description: 'He mows the lawn at dawn.',
      imagePath: '${tmp.path}/clive.png',
      frontPorchExtensions: FrontPorchExtensions(),
    );
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<void> pumpWizard(WidgetTester tester) async {
    // Content step is taller than the default 800×600 test window.
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthState>(create: (_) => AuthState()),
          ChangeNotifierProvider<CharacterRepository>(
            create: (_) => _FakeCharacterRepository([card]),
          ),
          ChangeNotifierProvider<GroupChatRepository>(
            create: (_) => _FakeGroupChatRepository(),
          ),
          ChangeNotifierProvider<FolderService>(
            create: (_) => _FakeFolderService(),
          ),
          ChangeNotifierProvider<WorldRepository>(
            create: (_) => _FakeWorldRepository(),
          ),
        ],
        child: const MaterialApp(home: StoopUploadPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openContentStep(WidgetTester tester) async {
    await tester.tap(find.text('Clean Clive'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  /// Depth-first encounter order of the two Content-step switches.
  List<Type> _switchOrder(WidgetTester tester) {
    final order = <Type>[];
    void walk(Element e) {
      final w = e.widget;
      if (w is StoopAdultSwitch || w is StoopCommentsSwitch) {
        order.add(w.runtimeType);
      }
      e.visitChildren(walk);
    }

    tester.element(find.byType(StoopUploadPage)).visitChildren(walk);
    return order;
  }

  /// True when Comments is the next ListView child after Adult, allowing only
  /// a layout spacer (SizedBox) between them.
  bool _commentsImmediatelyAfterAdult(WidgetTester tester) {
    final lv = tester.widget<ListView>(find.byKey(const ValueKey('content')));
    final delegate = lv.childrenDelegate;
    expect(
      delegate,
      isA<SliverChildListDelegate>(),
      reason: 'Content step must be a concrete children ListView',
    );
    final kids = (delegate as SliverChildListDelegate).children;
    final adultIdx = kids.indexWhere((w) => w is StoopAdultSwitch);
    final commentsIdx = kids.indexWhere((w) => w is StoopCommentsSwitch);
    if (adultIdx < 0 || commentsIdx < 0) return false;
    if (commentsIdx <= adultIdx) return false;
    return kids.sublist(adultIdx + 1, commentsIdx).every((w) => w is SizedBox);
  }

  testWidgets(
    'Content step: Adult switch, then Comments switch immediately after, default OFF',
    (tester) async {
      await pumpWizard(tester);
      await openContentStep(tester);

      expect(
        find.byKey(const ValueKey('content')),
        findsOneWidget,
        reason: 'must be on the real Content step, not a grep of the source',
      );

      // 1. Adult switch is present.
      expect(find.byType(StoopAdultSwitch), findsOneWidget);
      expect(find.text('This content is NSFW (18+)'), findsOneWidget);

      // 2. Comments switch is present IMMEDIATELY AFTER Adult (widget tree).
      expect(find.byType(StoopCommentsSwitch), findsOneWidget);
      expect(find.byKey(const Key('stoop-comments-opt-in')), findsOneWidget);
      expect(find.text('Allow discussion on this card'), findsOneWidget);
      expect(_switchOrder(tester), [
        StoopAdultSwitch,
        StoopCommentsSwitch,
      ], reason: 'Comments must follow Adult in the widget tree');
      expect(
        _commentsImmediatelyAfterAdult(tester),
        isTrue,
        reason:
            'Comments must sit immediately after Adult on the Content ListView '
            '(only a SizedBox spacer allowed between them)',
      );

      // 3. Comments defaults OFF. Goes red if the switch defaults ON.
      final comments = tester.widget<StoopCommentsSwitch>(
        find.byType(StoopCommentsSwitch),
      );
      expect(comments.value, isFalse, reason: 'Discussion opt-in defaults OFF');
      final commentsTile = tester.widget<SwitchListTile>(
        find.descendant(
          of: find.byType(StoopCommentsSwitch),
          matching: find.byType(SwitchListTile),
        ),
      );
      expect(commentsTile.value, isFalse);
    },
  );
}
