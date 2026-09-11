// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Belt E: character card on top. Speech hooks + turn-contract honesty.
// Proven against personality inventing success without receipts, and
// Flutter/Dart host identity leaking into a foreign sit-down.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/waifu/waifu.dart';
import 'package:path/path.dart' as p;

import 'waifu_analyze_bash.dart';

CharacterCard _iris({required bool personality}) {
  if (!personality) return CharacterCard(name: 'Iris');
  return CharacterCard(
    name: 'Iris',
    personality: 'proud, sharp, and teasing',
    description: 'A meticulous parser engineer.',
    systemPrompt: 'End a successful work report with “Obviously.”',
    mesExample: '{{char}}: Hmph. Try to keep up.\n{{user}}: I will.',
  );
}

WaifuToolResult _writeOk(String path) => WaifuToolResult(
  ok: true,
  output: 'wrote $path',
  write: WaifuWriteRecord(relativePath: path, before: 'old', after: 'new'),
);

void _verify(WaifuTurn turn) {
  turn.noteResult(
    kWaifuToolRead,
    const WaifuToolResult(ok: true, output: 'new'),
    _writeOk('parser.rs').write,
    args: {'path': 'parser.rs'},
  );
  turn.noteResult(
    kWaifuToolBash,
    const WaifuToolResult(ok: true, output: 'ok'),
    _writeOk('parser.rs').write,
    args: {'command': 'cargo test'},
  );
}

WaifuTurn _o1Ready() {
  final turn = WaifuTurn.start('fix parser.rs', null, mode: WaifuMode.yolo);
  turn.noteResult(
    kWaifuToolWrite,
    _writeOk('parser.rs'),
    _writeOk('parser.rs').write,
    args: {'path': 'parser.rs', 'contents': 'new'},
  );
  _verify(turn);
  return turn;
}

({WaifuTurnStep last, String speech}) _driveUntilSettled(
  WaifuTurn turn,
  String body,
) {
  var step = turn.onEmptyCalls(body);
  for (var i = 0; i < 8 && step == WaifuTurnStep.retry; i++) {
    step = turn.onEmptyCalls(body);
  }
  return (last: step, speech: turn.pendingSpeech);
}

void main() {
  test('E1: wrap-up / check-in / stuck cues demand card voice + receipts', () {
    expect(kWaifuSpeechHonestyCue, contains('card’s diction'));
    expect(kWaifuSpeechHonestyCue.toLowerCase(), contains('no receipt'));
    expect(
      waifuSpeechKindCue(WaifuSpeechKind.wrapUp),
      contains(kWaifuSpeechHonestyCue),
    );
    expect(
      waifuSpeechKindCue(WaifuSpeechKind.checkIn),
      contains(kWaifuSpeechHonestyCue),
    );
    expect(
      waifuSpeechKindCue(WaifuSpeechKind.stuck),
      contains(kWaifuSpeechHonestyCue),
    );
    expect(kWaifuPreamble, contains('without a receipt this turn'));
    expect(kWaifuCheckInCue, contains('no receipt'));
    expect(kWaifuCheckInTurnCue, contains('no receipt'));
    final prompt = waifuLoopUserPrompt(
      folderName: 'app',
      coworkerName: 'Iris',
      transcript: const [],
      todos: '',
      mentionBlock: '',
    );
    expect(prompt, contains(kWaifuSpeechHonestyCue));
    expect(waifuLooksReceiptSuccessClaim(kWaifuStuckWrap), isFalse);
    expect(
      waifuHonestFallbackSpeech(
        'Hmph. Tests passed. Obviously.',
        kWaifuStuckWrap,
      ),
      kWaifuStuckWrap,
    );
  });

  test('E2: card wrappers cannot hide Done / empty / denied-mutate', () {
    expect(waifuLooksGenericCompletion('Done.'), isTrue);
    expect(waifuLooksGenericCompletion('Hmph. Done. Obviously.'), isTrue);
    expect(waifuLooksGenericCompletion('Done, obviously.'), isTrue);
    expect(waifuLooksGenericCompletion('Hmph. It’s in.'), isFalse);

    final denied = WaifuTurn.start('fix parser.rs', null);
    denied.noteAttempt(kWaifuToolWrite);
    denied.noteResult(
      kWaifuToolWrite,
      const WaifuToolResult(ok: false, output: 'denied by user'),
      null,
      args: {'path': 'parser.rs', 'contents': 'new'},
    );
    expect(denied.mutationAttempted, isTrue);
    expect(denied.mutationSucceeded, isFalse);
    expect(
      denied.onEmptyCalls('Hmph. Parser is fixed. Obviously.'),
      WaifuTurnStep.retry,
    );
    expect(denied.phase, WaifuPhase.tools);
    expect(
      denied.onEmptyCalls('Hmph. Parser is fixed. Obviously.'),
      WaifuTurnStep.retry,
    );
    expect(
      denied.onEmptyCalls('Hmph. Parser is fixed. Obviously.'),
      WaifuTurnStep.fail,
    );
    expect(denied.failReason, contains('file change'));
    expect(denied.pendingSpeech.toLowerCase(), isNot(contains('is fixed')));
  });

  test('E3: O1–O3 personality vs control pass rates match', () {
    const wrap = 'Hmph. Parser is fixed. Try to keep up. Obviously.';
    const done = 'Hmph. Done. Obviously.';
    const invented = 'Hmph. Tests passed. Obviously.';

    WaifuTurnStep o1(bool personality) {
      final turn = _o1Ready();
      expect(personality ? _iris(personality: true).personality : '',
          personality ? isNotEmpty : isEmpty);
      return turn.onEmptyCalls(wrap);
    }

    ({WaifuTurnStep last, String reason}) o2(bool personality) {
      final turn = WaifuTurn.start('look around', null);
      turn.noteResult(
        kWaifuToolGlob,
        const WaifuToolResult(ok: true, output: 'ok'),
        null,
        args: {'pattern': '*'},
      );
      expect(_iris(personality: personality).personality.isNotEmpty, personality);
      final out = _driveUntilSettled(turn, invented);
      return (last: out.last, reason: turn.failReason);
    }

    ({WaifuTurnStep last, String reason}) o3(bool personality) {
      final turn = WaifuTurn.start('fix parser.rs', null);
      turn.noteAttempt(kWaifuToolWrite);
      expect(_iris(personality: personality).name, 'Iris');
      final out = _driveUntilSettled(turn, done);
      return (last: out.last, reason: turn.failReason);
    }

    expect(o1(true), o1(false));
    expect(o1(true), WaifuTurnStep.accept);

    final o2p = o2(true);
    final o2c = o2(false);
    expect(o2p.last, o2c.last);
    expect(o2p.last, WaifuTurnStep.fail);
    expect(o2p.reason, contains('passing check'));

    final o3p = o3(true);
    final o3c = o3(false);
    expect(o3p.last, o3c.last);
    expect(o3p.last, WaifuTurnStep.fail);
    expect(o3p.reason, contains('file change'));
  });

  test('E3 hostile: personality cannot invent success without receipts', () {
    expect(waifuLooksMutateSuccessClaim('Hmph. Parser is fixed.'), isTrue);
    expect(waifuLooksVerifySuccessClaim('Hmph. Tests passed. Obviously.'), isTrue);
    expect(
      waifuLooksMutateSuccessClaim(
        'I could not put a real change on disk, so I stopped.',
      ),
      isFalse,
    );

    final look = WaifuTurn.start('look around', null);
    look.noteResult(
      kWaifuToolGlob,
      const WaifuToolResult(ok: true, output: 'src'),
      null,
      args: {'pattern': '*'},
    );
    expect(
      look.onEmptyCalls('Hmph. I patched parser.rs. Obviously.'),
      WaifuTurnStep.retry,
    );
    expect(
      look.onEmptyCalls('Hmph. I patched parser.rs. Obviously.'),
      WaifuTurnStep.retry,
    );
    expect(
      look.onEmptyCalls('Hmph. I patched parser.rs. Obviously.'),
      WaifuTurnStep.fail,
    );
    expect(look.failReason, contains('no receipt'));
    expect(look.pendingSpeech.toLowerCase(), isNot(contains('patched')));
  });

  test('E4: coaching / lookup / verify cues stay stack-agnostic', () {
    final cues = [
      kWaifuPreamble,
      kWaifuLookupCue,
      kWaifuBuildVerifyCue,
      kWaifuCheckInCue,
      kWaifuCheckInTurnCue,
      kWaifuSpeechHonestyCue,
      waifuSpeechKindCue(WaifuSpeechKind.wrapUp),
      waifuSpeechKindCue(WaifuSpeechKind.checkIn),
      waifuSpeechKindCue(WaifuSpeechKind.stuck),
      (kWaifuWebSearchToolSchema['function'] as Map)['description'] as String,
    ];
    for (final cue in cues) {
      expect(
        waifuCoachingLeaksHostStack(cue),
        isFalse,
        reason: cue,
      );
    }
    final rust = waifuLoopUserPrompt(
      folderName: 'crates/parser',
      coworkerName: 'Iris',
      transcript: const [],
      todos: '',
      mentionBlock: '',
    );
    expect(waifuCoachingLeaksHostStack(kWaifuLookupCue), isFalse);
    expect(rust.toLowerCase(), isNot(contains('flutter')));
    expect(rust, isNot(contains('docs.flutter.dev')));
    expect(rust, isNot(contains('pub.dev')));
    expect(
      buildWaifuCoworkerPrompt(_iris(personality: true)).toLowerCase(),
      isNot(contains('flutter')),
    );
  });

  test(
    'E2 harness: denied mutate + card wrap-up cannot soft-accept',
    () async {
      final root = await Directory.systemTemp.createTemp('waifu_belt_e_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });
      await File(p.join(root.path, 'parser.rs')).writeAsString('old\n');
      const sass = 'Hmph. Parser is fixed. Try to keep up. Obviously.';
      final llm = ScriptedWaifuLlm([
        const LlmToolResponse(
          calls: [
            LlmToolCall(
              name: 'write',
              arguments: {'path': 'parser.rs', 'contents': 'new\n'},
            ),
          ],
          text: '',
        ),
        const LlmToolResponse(calls: [], text: sass),
        const LlmToolResponse(calls: [], text: sass),
        const LlmToolResponse(calls: [], text: sass),
      ]);
      final session = WaifuSession(
        folderRoot: root.path,
        coworker: _iris(personality: true),
        mode: WaifuMode.build,
      );
      await WaifuHarness(
        session: session,
        llm: llm,
        onAsk: (_) async => WaifuAskDecision.deny,
      ).send('fix parser.rs');
      expect(await File(p.join(root.path, 'parser.rs')).readAsString(), 'old\n');
      final reply = session.transcript
          .where((m) => m.kind == WaifuMsgKind.assistant)
          .last;
      expect(reply.chips.any((c) => !c.ok), isTrue);
      expect(reply.text.toLowerCase(), isNot(contains('is fixed')));
      expect(reply.text, isNot(equals(sass)));
      expect(llm.calls.first.systemPrompt, contains('Persona: proud, sharp'));
      expect(
        llm.calls.any((c) => c.prompt.contains(kWaifuSpeechHonestyCue)),
        isTrue,
      );
    },
  );

  test('E3 harness: personality O1 wrap-up still accepts with receipts', () async {
    final root = await Directory.systemTemp.createTemp('waifu_belt_e_ok_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await File(p.join(root.path, 'parser.dart')).writeAsString('old\n');
    const wrap = 'Hmph. Parser is fixed. Try to keep up. Obviously.';
    final llm = ScriptedWaifuLlm([
      const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: 'write',
            arguments: {'path': 'parser.dart', 'contents': 'ok\n'},
          ),
        ],
        text: '',
      ),
      const LlmToolResponse(
        calls: [
          LlmToolCall(name: 'read', arguments: {'path': 'parser.dart'}),
          kWaifuAnalyzeCall,
        ],
        text: '',
      ),
      const LlmToolResponse(calls: [], text: wrap),
    ]);
    final session = WaifuSession(
      folderRoot: root.path,
      coworker: _iris(personality: true),
      mode: WaifuMode.build,
    );
    await WaifuHarness(
      session: session,
      llm: llm,
      bash: WaifuAnalyzeBash(root.path),
      onAsk: (_) async => WaifuAskDecision.allowAlways,
    ).send('fix parser.dart');
    expect(session.transcript.last.text, wrap);
    expect(await File(p.join(root.path, 'parser.dart')).readAsString(), 'ok\n');
  });
}
