// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// In-process stand-in for an unmanaged OpenAI-compatible local backend (the
// PseudoRemote path: LM Studio / llama.cpp servers). Serves the endpoints
// observed during a realism-enabled chat turn plus the KoboldCpp extras a
// managed-mode run would use (kept modeled; unused paths cost nothing and
// unmodeled ones fail the traffic audit by name):
//
//   GET  /api/extra/version      health probe
//   GET  /api/extra/perf         perf poll (idle/queue/speeds)
//   POST /api/extra/tokencount   real-tokenizer prompt counts
//   POST /v1/chat/completions    OpenAI-compatible SSE (the protocol
//                                KoboldService.generateStream actually speaks
//                                via streamOpenAiChat)
//
// Completion routing: a request whose body contains a "tools" array is the
// tool-transport probe — it is refused with 404 so the app falls back to the
// text eval path (the fallback is itself production code worth exercising).
// A text request is classified by the JSON keys its prompt asks the model to
// produce: realism eval prompts name their keys (relationship_delta,
// emotion_intensity, fixation_topic, with_user, ...), so the fake answers
// with a valid canned payload for exactly the keys requested. Anything else
// is the user chat turn and streams [replyPieces] as multiple SSE chunks
// (proving the incremental decode path).

import 'dart:convert';
import 'dart:io';

class FakeBackendServer {
  FakeBackendServer._(this._server, this.replyPieces, this.chatChunkDelay);

  final HttpServer _server;

  /// The chat reply, streamed one SSE chunk per element.
  final List<String> replyPieces;

  /// Pause before EACH chat-reply chunk (including the first — that is what
  /// actually opens a cancel window; a between-chunks-only delay lets chunk 1
  /// land instantly). Applies ONLY to conversation turns: evals, journal,
  /// growth and story stages stay instant, so a paced suite doesn't multiply
  /// every background call by the delay and blow its own waits.
  final Duration chatChunkDelay;

  /// Non-eval chat completions served (the actual conversation turns).
  int chatRequests = 0;

  /// Realism/eval completions served (classified by requested JSON keys).
  int evalRequests = 0;

  /// Journal maintenance passes served (XML transport exchanges).
  int journalPassRequests = 0;

  /// Growth passes served (the `<ring>` XML transport). Without this branch a
  /// growth prompt fell through to the CHAT handler: chatRequests bumped,
  /// lastChatBody clobbered, and the canned reply had no `<ring>` tags — an
  /// honest "no growth" that silently advanced the cursor forever.
  int growthPassRequests = 0;

  /// Objective task-generation requests served (numbered-list format).
  int objectiveTaskRequests = 0;

  /// Story pipeline stages served, in order (architect / acts / scenes /
  /// beats / prose) — the story suite asserts the exact sequence.
  final List<String> storyStagesServed = [];

  /// Tool-transport probes refused (forces the text eval fallback).
  int toolProbeRequests = 0;

  /// Manual needs-reprocess hook. A completion whose prompt carries
  /// [reprocessMarker] is answered with [reprocessDeltas] instead of the
  /// standard canned needs set. Set the deltas to something DIFFERENT on every
  /// key: a scoped pass can then be proven to move only the needs it was given
  /// and leave the rest exactly where the turn put them — with one shared reply
  /// you cannot tell "correctly ignored" from "happened to match".
  String? reprocessMarker;
  Map<String, int> reprocessDeltas = const {};
  int reprocessRequests = 0;

  /// Body of the most recent NON-eval chat completion — lets the test prove
  /// the user's message actually reached the outbound prompt.
  String lastChatBody = '';

  /// When set, a conversation turn whose prompt contains this marker is
  /// answered with HTTP 500 instead of a stream, then this clears itself.
  /// Models the everyday failure a local backend actually produces (model
  /// unloaded, OOM, server restarted) so the suite can prove the app reports
  /// it and — critically — releases its in-flight guards rather than wedging
  /// the composer forever.
  ///
  /// Marker-matched, not "next request": an untargeted flag is a race. The
  /// app fires background chat-shaped completions (the objective completion
  /// check is the one that bit us) which are classified CHAT by this fake, so
  /// on a slower machine one of THOSE consumed the injected failure while the
  /// real user turn succeeded. That desynchronised the whole phase and turned
  /// a deterministic test into a platform-dependent one — green on the dev
  /// Mac, red on the macOS and Windows CI runners.
  String? failChatCompletionContaining;

  /// Conversation turns rejected via [failNextChatCompletion].
  int chatFailuresServed = 0;

  /// Paths the app hit that this fake doesn't model. Asserted empty: if a
  /// future change adds backend traffic to a chat turn, the failure names
  /// the endpoint instead of a silent 404 skewing behavior.
  final List<String> unexpectedPaths = [];

  String get baseUrl => 'http://127.0.0.1:${_server.port}';

  static Future<FakeBackendServer> start({
    required List<String> replyPieces,
    Duration chatChunkDelay = Duration.zero,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    // Always own a growable copy. Suites pass const lists (or want to
    // clear/replace mid-test for Continue), and mutating a const/unmodifiable
    // list throws UnsupportedError mid-suite — that is exactly how
    // continue_path_test red'd macOS + Windows CI (2026-08-11).
    final fake = FakeBackendServer._(
      server,
      List<String>.of(replyPieces),
      chatChunkDelay,
    );
    server.listen(fake._handle);
    return fake;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      switch (req.uri.path) {
        case '/api/extra/version':
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({'result': 'KoboldCpp', 'version': '1.100'}),
          );
        case '/api/extra/perf':
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'last_process_speed': 100.0,
              'last_eval_speed': 50.0,
              'last_input_count': 32,
              'last_token_count': 16,
              'total_gens': chatRequests + evalRequests,
              'queue': 0,
              'idle': 1,
            }),
          );
        case '/v1/models':
          // OpenAI-compatible model listing — the remote backend service
          // fetches this to populate/validate the model picker.
          req.response.headers.contentType = ContentType.json;
          req.response.write(
            jsonEncode({
              'data': [
                {'id': 'smoke-model'},
              ],
            }),
          );
        case '/api/extra/tokencount':
          final body = await utf8.decodeStream(req);
          final prompt = (jsonDecode(body)['prompt'] as String?) ?? '';
          req.response.headers.contentType = ContentType.json;
          // Deterministic pseudo-tokenizer: close enough for prefill math.
          req.response.write(jsonEncode({'value': (prompt.length / 4).ceil()}));
        case '/v1/chat/completions':
          await _handleCompletion(req);
        // Capability probes where 404 IS the correct answer: the remote
        // backend sniffs LM Studio's native API to detect what it's talking
        // to, and answering it would misidentify this fake as LM Studio.
        case '/api/v0/models':
          req.response.statusCode = HttpStatus.notFound;
        default:
          unexpectedPaths.add(req.uri.path);
          req.response.statusCode = HttpStatus.notFound;
      }
    } catch (e) {
      // Usually a request racing test teardown (closed socket) — but logged,
      // so a genuine handler bug (bad JSON, write failure) can't hide here.
      // ignore: avoid_print — test support; print reaches the suite log.
      print('[FakeBackendServer] handler error on ${req.uri.path}: $e');
    } finally {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _handleCompletion(HttpRequest req) async {
    final body = await utf8.decodeStream(req);

    // Real JSON field check, not a substring test: a quoted "tools" inside
    // message content must not trip the probe branch.
    Map<String, dynamic> decoded = const {};
    try {
      decoded = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      // Malformed body → key routing below still works on the raw text.
    }
    if (decoded['tools'] != null) {
      toolProbeRequests++;
      req.response.statusCode = HttpStatus.notFound;
      req.response.write(
        jsonEncode({
          'error': {'message': 'tools transport not supported by this fake'},
        }),
      );
      return;
    }

    // Classify on the LAST message's content only. Eval prompts end with
    // instructions naming the JSON keys to emit; a realism-enabled CHAT
    // request carries realism-state injection text in its SYSTEM prompt
    // (posture, bond words...) that would false-match a whole-body search —
    // that exact misroute happened: turn 2's generation was answered with
    // eval JSON. The last message is the typed user text for chat and the
    // instruction block for evals.
    String lastContent = body;
    final messages = decoded['messages'];
    if (messages is List && messages.isNotEmpty) {
      final last = messages.last;
      if (last is Map && last['content'] is String) {
        lastContent = last['content'] as String;
      }
    }
    // Journal maintenance pass — its prompt teaches the <memory> tag. Checked
    // before the JSON evals because the pass prompt can mention other terms.
    if (lastContent.contains('<memory')) {
      journalPassRequests++;
      await _streamSse(req, [
        '<memory action=add category=moment msgs="1 2">'
            'The porch swing creaked as they talked.</memory>\n'
            '<recap>Two friends warming up on the porch.</recap>',
      ]);
      return;
    }
    // Growth pass — its prompt teaches the <ring> tag (buildGrowthPrompt's
    // XML transport). Same precedence rationale as the journal branch. The
    // src receipt points at message position 1 so the receipts-jump E2E has
    // a real target to seek.
    if (lastContent.contains('<ring')) {
      growthPassRequests++;
      await _streamSse(req, [
        '<ring action="add" category="stance" src="1">'
            'Has started saving the porch swing for their favorite guest.'
            '</ring>',
      ]);
      return;
    }
    // ── Story pipeline stages ──────────────────────────────────────────
    // Each stage prompt opens with a distinctive role sentence (verified
    // against story_pipeline_service.dart's prompt builders); none of them
    // carry the eval JSON keys below, so precedence here only guards against
    // the CHAT fallthrough (whose canned replyPieces would fail the
    // pipeline's JSON parse). The fake returns a MINIMAL story — 1 act,
    // 1 scene, 1 beat — so the full concept→prose journey is 5 LLM calls.
    if (lastContent.contains('You are a Lead Narrative Designer.') ||
        lastContent.contains('Create a story bible from the concept.')) {
      storyStagesServed.add('architect');
      await _streamSse(req, [
        jsonEncode({
          'concept': 'A porch light that never goes out.',
          'status_quo': 'Wren tends the porch alone each evening.',
          'inciting_incident': 'One night the light flickers a message.',
          'themes': 'Belonging, small kindnesses',
          'style': {
            'genre': 'Cozy fantasy',
            'mood': 'Warm',
            'writing_guide': 'Short sentences. Concrete detail.',
          },
          'threads': [
            {
              'id': 't1',
              'name': 'The flickering light',
              'description': 'What the porch light is trying to say.',
            },
          ],
          'protagonist': {
            'name': 'Wren',
            'role': 'Protagonist',
            'description': 'Keeper of the porch light.',
          },
          'world_lore': [
            {'topic': 'The Porch', 'detail': 'It remembers every guest.'},
          ],
        }),
      ]);
      return;
    }
    if (lastContent.contains('You are an author developing story structure.')) {
      storyStagesServed.add('acts');
      await _streamSse(req, [
        jsonEncode({
          'acts': [
            {
              'number': 1,
              'title': 'The Message in the Light',
              'description': 'Wren decodes the flicker and answers it.',
              'focus_thread_ids': ['t1'],
              'knots': [],
            },
          ],
        }),
      ]);
      return;
    }
    if (lastContent.contains('You are an author creating scenes for ACT')) {
      storyStagesServed.add('scenes');
      await _streamSse(req, [
        jsonEncode({
          'scenes': [
            {
              'number': 1,
              'title': 'Reading the Flicker',
              'description': 'Wren counts the pulses and writes them down.',
              'active_thread_ids': ['t1'],
              'location': 'The front porch',
              'cast_names': ['Wren'],
              'valence': 2,
              'causality': {
                'interaction_type': 'Isolation',
                'description': 'A quiet solo discovery.',
              },
            },
          ],
          'new_characters': [],
        }),
      ]);
      return;
    }
    if (lastContent.contains(
      'You are the architect of a single narrative scene.',
    )) {
      storyStagesServed.add('beats');
      await _streamSse(req, [
        jsonEncode({
          'beats': [
            {
              'number': 1,
              'type': 'Revelation',
              'description': 'The flicker spells a single word: stay.',
              'emotional_shift': 'wary to moved',
              'valence': 4,
              'pacing': 1,
            },
          ],
        }),
      ]);
      return;
    }
    // ── Auto-Write stages (Drafter → Editor → Validator → Archivist) ───
    // A DIFFERENT path from the 'prose' branch below: generateFullAct writes a
    // scene in one combined call, while the writer page's Auto-Write runs these
    // four per beat. Both exist in the app, so both are modeled.
    if (lastContent.contains(
      'You are an award-winning author working on your next novel.',
    )) {
      storyStagesServed.add('drafter');
      await _streamSse(req, [
        'The lamp guttered once. ',
        'Wren did not move to steady it.',
      ]);
      return;
    }
    if (lastContent.contains('You are a Ruthless Editor.')) {
      storyStagesServed.add('editor');
      await _streamSse(req, [
        'The lamp guttered once, and Wren let it. Some things keep '
            'themselves alight.',
      ]);
      return;
    }
    if (lastContent.contains('You are a Script Doctor.')) {
      storyStagesServed.add('validator');
      await _streamSse(req, [
        jsonEncode({'valid': true, 'reason': '', 'rectified_beats': []}),
      ]);
      return;
    }
    if (lastContent.contains('You are the Story Archivist.')) {
      storyStagesServed.add('archivist');
      // Deliberately empty updates: the archivist's PARSE is what this
      // exercises; inventing cast edits would couple the suite to its schema.
      await _streamSse(req, [
        jsonEncode({'cast_updates': [], 'world_lore': []}),
      ]);
      return;
    }
    if (lastContent.contains(
      'You are a skilled novelist writing one section of a larger scene.',
    )) {
      storyStagesServed.add('prose');
      // Multiple chunks on purpose: tokenCount increments once per stream
      // event, and the running overlay's 'N tokens generated' line is the
      // suite's streaming assertion.
      await _streamSse(req, [
        'The porch light blinked, ',
        'paused, and blinked again. ',
        'Wren counted the pulses twice before believing them: ',
        'stay.',
      ]);
      return;
    }

    // Objective task generation — plain numbered-list format, not JSON.
    if (lastContent.contains('numbered list of exactly') ||
        lastContent.contains('report_objective_tasks')) {
      objectiveTaskRequests++;
      await _streamSse(req, [
        '1. Pour two glasses of lemonade.\n'
            '2. Pat the seat of the porch swing.\n'
            '3. Tell the story of the creaky board.\n'
            '4. Ask about their favorite weather.\n'
            '5. Watch the sunset together.',
      ]);
      return;
    }
    if (lastContent.contains('Evaluate EACH item below') ||
        lastContent.contains('report_objective_verdicts')) {
      await _streamSse(req, ['1: NO']);
      return;
    }

    // Manual needs reprocess — checked BEFORE the eval keys below, because a
    // reprocess prompt is a needs-impact prompt and would otherwise be answered
    // with the same canned set the original turn got.
    final reprocess = reprocessMarker;
    if (reprocess != null &&
        reprocess.isNotEmpty &&
        lastContent.contains(reprocess)) {
      reprocessRequests++;
      await _streamSse(req, [
        jsonEncode({
          for (final e in reprocessDeltas.entries) '${e.key}_delta': e.value,
        }),
      ]);
      return;
    }

    final eval = <String, dynamic>{};
    if (lastContent.contains('relationship_delta')) {
      // 13 on purpose: |bond delta| >= 12 is the salience threshold that
      // kicks an immediate journal maintenance pass (clamp allows ±15).
      eval['relationship_delta'] = 13;
      eval['trust_delta'] = 1;
      eval['bond_reason'] = 'smoke-test warmth';
      eval['trust_reason'] = 'smoke-test honesty';
    }
    if (lastContent.contains('hunger_delta')) {
      eval['hunger_delta'] = -4;
      eval['energy_delta'] = -2;
      eval['hygiene_delta'] = 0;
      eval['fun_delta'] = 6;
      eval['social_delta'] = 5;
      eval['bladder_delta'] = -3;
      eval['comfort_delta'] = 2;
    }
    // Climax detection. Its OWN eval since Afterglow was decoupled from Needs
    // (e943ba2) — it used to ride the needs-impact eval, which is why the
    // verdict was produced in the hunger_delta branch above.
    //
    // Without this branch the standalone call matches nothing, falls through to
    // the CHAT branch, is answered with prose, and detection silently fails —
    // which is exactly how it reached CI. Worse, it also incremented
    // chatRequests, the counter the scene-time comment below is careful to keep
    // trustworthy.
    //
    // TRUE only when the scene the eval quotes contains the marker phrase 'the
    // wave crests', which only climax_refractory_test.dart ever sends, so every
    // other suite keeps its existing behavior. Note the phrase arrives in the
    // "Recent exchange for context" section, not the reply: the user narrates
    // the climax and the character answers with aftermath, which is the common
    // shape in roleplay and the reason that context is in the prompt at all.
    if (lastContent.contains('"is_climax"')) {
      final climax = lastContent.contains('the wave crests');
      eval['is_climax'] = climax;
      eval['refractory_turns'] = climax ? 6 : 0;
    }
    if (lastContent.contains('emotion_intensity')) {
      eval['emotion'] = 'happy';
      eval['emotion_intensity'] = 'moderate';
    }
    if (lastContent.contains('fixation_topic')) {
      eval['fixation_topic'] = 'none';
      // A real objective, so the proposal machinery (dedup, autonomous
      // task-gen) actually runs instead of short-circuiting on 'none'.
      eval['proposed_objective'] = 'Share porch lemonade before sunset';
    }
    // Scene-time / physical-state eval. Modeled so it can never misroute
    // into the chat branch — chatRequests and lastChatBody stay trustworthy.
    if (lastContent.contains('minutes_elapsed') ||
        lastContent.contains('"posture"')) {
      eval['posture'] = 'standing';
      eval['minutes_elapsed'] = 5;
      eval['new_day'] = false;
    }
    // Glance pass (21bfd8c3). Same trap as climax above: unmatched key
    // falls through to CHAT, bumps chatRequests, clobbers lastChatBody —
    // group_smoke, group_realism_wiring, and lorebook_chat all red that way.
    if (lastContent.contains('"with_user"')) {
      eval['with_user'] = true;
    }

    // One line per completion so a misclassification is visible in the suite
    // log without any debugger. ignore: avoid_print — test support.
    print(
      '[FakeBackendServer] completion: ${eval.isEmpty ? 'CHAT' : 'EVAL(${eval.keys.join('+')})'} '
      'last="${lastContent.length > 70 ? lastContent.substring(lastContent.length - 70) : lastContent}"',
    );

    if (eval.isNotEmpty) {
      evalRequests++;
      // The whole eval JSON rides one content delta — the parser regex/JSON
      // extraction works on the assembled text either way.
      await _streamSse(req, [jsonEncode(eval)]);
      return;
    }

    // Injected failure: only conversation turns, never evals, so a resilience
    // phase cannot accidentally starve the realism pipeline it runs after —
    // and only the turn actually carrying the marker.
    final marker = failChatCompletionContaining;
    if (marker != null && body.contains(marker)) {
      failChatCompletionContaining = null;
      chatFailuresServed++;
      req.response.statusCode = HttpStatus.internalServerError;
      req.response.headers.contentType = ContentType.json;
      req.response.write(
        jsonEncode({
          'error': {'message': 'smoke-test injected backend failure'},
        }),
      );
      return;
    }

    chatRequests++;
    lastChatBody = body;
    await _streamSse(req, replyPieces, delay: chatChunkDelay);
  }

  Future<void> _streamSse(
    HttpRequest req,
    List<String> pieces, {
    Duration delay = Duration.zero,
  }) async {
    req.response.headers.set('Content-Type', 'text/event-stream');
    // MANDATORY for a real stream, and flush() alone is NOT enough: Dart's
    // HttpResponse buffers output by default and only hands the buffer to the
    // socket when the response CLOSES, so every "paced" chunk below arrived at
    // the client in one burst at the end. The app then saw zero tokens for the
    // whole generation and the full reply in a single step — which is exactly
    // why the cancel-mid-regenerate phase could never observe a partial. Proven
    // in isolation: with bufferOutput left true, chunk 1 lands at +1676ms
    // (stream end); with it false, at +405ms.
    req.response.bufferOutput = false;
    for (final piece in pieces) {
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      req.response.write(
        'data: ${jsonEncode({
          'choices': [
            {
              'delta': {'content': piece},
            },
          ],
        })}\n\n',
      );
      await req.response.flush();
    }
    req.response.write('data: [DONE]\n\n');
    await req.response.flush();
  }

  Future<void> close() => _server.close(force: true);
}
