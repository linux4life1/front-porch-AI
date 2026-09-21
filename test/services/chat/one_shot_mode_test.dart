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

// ONE-SHOT IS A TRI-STATE NOW, AND AUTO IS THE DEFAULT.
//
// Auto fuses the pre-generation judges into one call exactly where the fused
// prompt is safe — a REMOTE backend that has PROVEN native tool calls this
// run — and keeps the multi-call path everywhere else, including every local
// backend (small models struggling with the combined length is the reason
// the old bool defaulted off). The explicit modes always win, in both
// directions.
//
// Pinned here: the resolution truth table (pure), the migration from the old
// bool (an explicit true was an opt-in and stays ON; false was the
// indistinguishable old default and becomes Auto), the legacy bool shim
// (a toggle is an explicit choice — On/Off, never Auto — and keeps writing
// the old key the persistence test reads), and the wiring (all three
// consultation sites resolve through the ONE getter, so the dance, the regen
// replay and the retroactive baseline scan can never disagree about which
// path a turn takes).
//
// Proven-to-fail note (the mandatory negative check, run 2026-08-10 before
// this file was allowed to land): inverting the Auto branch of
// resolveOneShotMode turned the truth-table group red; reverting the dance's
// call site to the old bool read turned the wiring guard red. Both were
// restored and the suite went green again.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/chat/pass_support.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_oneshot_').path;
        }
        return null;
      });
}

Future<StorageService> _boot(Map<String, Object> prefs) async {
  SharedPreferences.setMockInitialValues(prefs);
  final svc = StorageService();
  await svc.initialized;
  return svc;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  group('the resolution truth table', () {
    test('On and Off win in both directions, whatever the backend', () {
      for (final isLocal in [true, false]) {
        for (final support in ToolCallSupport.values) {
          expect(
            resolveOneShotMode(
              mode: OneShotMode.on,
              isLocal: isLocal,
              toolSupport: support,
            ),
            isTrue,
          );
          expect(
            resolveOneShotMode(
              mode: OneShotMode.off,
              isLocal: isLocal,
              toolSupport: support,
            ),
            isFalse,
          );
        }
      }
    });

    test('Auto fuses only on a remote backend with proven tools', () {
      expect(
        resolveOneShotMode(
          mode: OneShotMode.auto,
          isLocal: false,
          toolSupport: ToolCallSupport.supported,
        ),
        isTrue,
        reason:
            'a tools-confirmed remote model is exactly the class the '
            'fused prompt is easy for — this is the case Auto exists to catch',
      );
      expect(
        resolveOneShotMode(
          mode: OneShotMode.auto,
          isLocal: true,
          toolSupport: ToolCallSupport.supported,
        ),
        isFalse,
        reason:
            'local stays multi-call even with tools — the combined '
            'prompt length is the risk there, not the transport',
      );
      for (final support in [
        ToolCallSupport.untested,
        ToolCallSupport.unsupported,
      ]) {
        expect(
          resolveOneShotMode(
            mode: OneShotMode.auto,
            isLocal: false,
            toolSupport: support,
          ),
          isFalse,
          reason:
              'an unproven backend gets the conservative path; the first '
              'eval of the run probes and Auto converges next turn',
        );
      }
    });
  });

  group('migration from the old bool', () {
    test('a fresh install defaults to Auto', () async {
      final svc = await _boot({});
      expect(svc.realismSettings.oneShotMode, OneShotMode.auto);
    });

    test('an explicit old true was an opt-in and stays ON', () async {
      final svc = await _boot({'realism_one_shot_eval': true});
      expect(svc.realismSettings.oneShotMode, OneShotMode.on);
    });

    test(
      'an old false was the indistinguishable default and becomes Auto',
      () async {
        final svc = await _boot({'realism_one_shot_eval': false});
        expect(svc.realismSettings.oneShotMode, OneShotMode.auto);
      },
    );

    test('the new key wins over the old bool once written', () async {
      final svc = await _boot({
        'realism_one_shot_mode': 'off',
        'realism_one_shot_eval': true,
      });
      expect(
        svc.realismSettings.oneShotMode,
        OneShotMode.off,
        reason:
            'a tri-state choice must never be overridden by the stale '
            'bool it superseded',
      );
    });

    test('the mode setter round-trips through prefs', () async {
      final svc = await _boot({});
      await svc.realismSettings.setOneShotMode(OneShotMode.on);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('realism_one_shot_mode'), 'on');
    });

    test('the legacy bool shim maps a toggle to On/Off, never Auto', () async {
      final svc = await _boot({});
      await svc.realismSettings.setRealismOneShotEval(true);
      expect(svc.realismSettings.oneShotMode, OneShotMode.on);
      expect(svc.realismSettings.realismOneShotEval, isTrue);
      await svc.realismSettings.setRealismOneShotEval(false);
      expect(
        svc.realismSettings.oneShotMode,
        OneShotMode.off,
        reason:
            'an explicit toggle is an explicit choice — mapping false '
            'back to Auto would silently re-enable fusion on remote backends '
            'for a user who just switched it off',
      );
    });
  });
}
