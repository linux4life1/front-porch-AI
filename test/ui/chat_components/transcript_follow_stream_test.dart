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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/chat_components/chat_components.dart';

class _GrowingTranscript extends StatefulWidget {
  const _GrowingTranscript({super.key, required this.controller});

  final ScrollController controller;

  @override
  State<_GrowingTranscript> createState() => _GrowingTranscriptState();
}

class _GrowingTranscriptState extends State<_GrowingTranscript> {
  double newestHeight = 40;

  void growTo(double height) => setState(() => newestHeight = height);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 400,
            height: 200,
            child: ListView(
              controller: widget.controller,
              reverse: false,
              children: [
                const SizedBox(height: 100, child: Text('OLDEST')),
                const SizedBox(height: 100, child: Text('OLDER')),
                const SizedBox(height: 100, child: Text('KEEP')),
                SizedBox(height: newestHeight, child: const Text('STREAM')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  test('followStreamingReplies defaults on and persists', () async {
    expect(UiSettings().followStreamingReplies, isTrue);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final first = UiSettings()..initializeBase(prefs, () {});
    first.load();
    expect(first.followStreamingReplies, isTrue);
    await first.setFollowStreamingReplies(false);
    expect(first.followStreamingReplies, isFalse);

    final second = UiSettings()..initializeBase(prefs, () {});
    second.load();
    expect(second.followStreamingReplies, isFalse);
  });

  test(
    'General places Follow streaming replies immediately above Dark Mode',
    () {
      final tab = File(
        'lib/ui/settings/tabs/general_tab.dart',
      ).readAsStringSync();
      final follow = tab.indexOf('Follow streaming replies');
      final dark = tab.indexOf('Dark Mode');
      expect(follow, greaterThan(-1));
      expect(dark, greaterThan(follow));
      expect(tab.contains('setFollowStreamingReplies'), isTrue);
    },
  );

  test('forward list, hold, and absorb stay ripped', () {
    final list = File(
      'lib/ui/chat_components/stage/chat_message_list.dart',
    ).readAsStringSync();
    expect(list.contains('reverse: false'), isTrue);
    expect(list.contains('CustomScrollView'), isFalse);
    expect(list.contains('heldTranscriptOffset'), isFalse);
    expect(list.contains('followTranscriptWhileStreaming'), isTrue);
    expect(list.contains('startOfStream:'), isTrue);
    expect(
      File(
        'lib/ui/chat_components/bubbles/selectable_bubble_body.dart',
      ).readAsStringSync().contains('bubble-body-scroll-absorb'),
      isFalse,
    );
    final helper = File(
      'lib/ui/chat_components/stage/transcript_auto_scroll.dart',
    ).readAsStringSync();
    expect(helper.contains('heldTranscriptOffset'), isFalse);
    expect(helper.contains('void applyTranscriptAutoScroll'), isTrue);
  });

  testWidgets(
    'ON at bottom follows token growth; OFF and scrolled-away do not',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = ScrollController();
      addTearDown(controller.dispose);
      final listKey = GlobalKey<_GrowingTranscriptState>();
      await tester.pumpWidget(
        _GrowingTranscript(key: listKey, controller: controller),
      );
      await tester.pump();
      expect(pinTranscriptToLatest(controller), isTrue);
      await tester.pump();
      final previousMax = controller.position.maxScrollExtent;
      expect(controller.offset, previousMax);

      listKey.currentState!.growTo(200);
      await tester.pump();
      expect(
        controller.offset,
        previousMax,
        reason: 'stock forward list does not chase until the helper runs',
      );
      expect(
        followTranscriptWhileStreaming(
          controller,
          followEnabled: true,
          generating: true,
          previousMax: previousMax,
        ),
        isTrue,
      );
      await tester.pump();
      expect(
        controller.offset,
        controller.position.maxScrollExtent,
        reason: 'ON + at bottom + generating pins to the new latest',
      );

      final grownMax = controller.position.maxScrollExtent;
      listKey.currentState!.growTo(280);
      await tester.pump();
      expect(
        followTranscriptWhileStreaming(
          controller,
          followEnabled: false,
          generating: true,
          previousMax: grownMax,
        ),
        isFalse,
      );
      expect(
        controller.offset,
        grownMax,
        reason: 'OFF must not chase — the Mac-pass no-chase lock',
      );

      controller.jumpTo(80);
      await tester.pump();
      listKey.currentState!.growTo(360);
      await tester.pump();
      expect(
        followTranscriptWhileStreaming(
          controller,
          followEnabled: true,
          generating: true,
          previousMax: controller.position.maxScrollExtent - 80,
        ),
        isFalse,
      );
      expect(controller.offset, 80, reason: 'scrolled away stays put');

      expect(
        followTranscriptWhileStreaming(
          controller,
          followEnabled: true,
          generating: true,
          previousMax: controller.position.maxScrollExtent,
          startOfStream: true,
        ),
        isTrue,
      );
      await tester.pump();
      expect(
        controller.offset,
        controller.position.maxScrollExtent,
        reason:
            'ON + send/stream start jumps to the live reply from mid-history',
      );

      controller.jumpTo(80);
      await tester.pump();
      expect(
        followTranscriptWhileStreaming(
          controller,
          followEnabled: false,
          generating: true,
          previousMax: controller.position.maxScrollExtent,
          startOfStream: true,
        ),
        isFalse,
      );
      expect(
        controller.offset,
        80,
        reason: 'OFF never jumps, even at stream start',
      );

      applyTranscriptAutoScroll(controller, generating: true);
      await tester.pump();
      expect(
        controller.offset,
        80,
        reason: 'legacy applyTranscriptAutoScroll stays a no-op',
      );
    },
  );
}
