// A KoboldCpp stand-in on a real loopback socket, copying the parts of its
// behaviour the slot keeper depends on: one live token list, five save slots
// in memory, a generation lock every request waits in (the four admin calls
// included), fast forward that re-reads only what differs from the live
// cache, and a client that leaves aborting the reply. A word is a token.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// One request the engine took, in the order it got the generation lock.
class FakeEngineRequest {
  FakeEngineRequest(this.kind, {this.slot});

  /// `chat`, `save`, `load`, `check` or `clear`.
  final String kind;
  final int? slot;

  /// Words of the prompt, role marks included, and how many of them the
  /// engine had to read: the prompt minus its start shared with the cache.
  List<String> prompt = const [];
  int processed = 0;
  int replyTokens = 0;

  /// Whether the call answered `success: true` (admin) or was served (chat).
  bool ok = true;
  bool cutShort = false;
  bool stream = false;
  bool hadTools = false;

  /// When the engine finished an admin call (after any hold on it).
  DateTime? endedAt;

  int get promptTokens => prompt.length;
  String get promptText => prompt.join(' ');

  /// A short name for failure messages.
  @override
  String toString() => switch (kind) {
    'chat' => 'chat(read $processed of $promptTokens)',
    _ => slot == null ? kind : '$kind[$slot]',
  };
}

class FakeEngineSlot {
  List<String> tokens = [];
  int bytes = 0;
}

class FakeKoboldEngine {
  FakeKoboldEngine._(this._server, this.slotCount);

  static Future<FakeKoboldEngine> start({int slots = 5}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return FakeKoboldEngine._(server, slots).._serve();
  }

  final HttpServer _server;
  String get baseUrl => 'http://127.0.0.1:${_server.port}';
  Future<void> close() => _server.close(force: true);

  // What a test switches.
  final int slotCount;

  /// Off: the four admin calls answer `success: false`, as without --admin.
  bool adminOn = true;
  bool failSaves = false;
  bool failLoads = false;
  bool failClears = false;

  /// When set, a load answers this HTTP status and nothing else.
  int? loadStatus;
  int bytesPerToken = 1000;
  int replyWords = 6;

  /// Called after the prompt is read and before the reply streams, so a test
  /// can hold a request mid-way. The request is already in [log].
  Future<void> Function(FakeEngineRequest request)? beforeReply;

  /// The same for the admin calls: held inside the lock before the call is
  /// carried out, as a slow copy of a big cache would be.
  Future<void> Function(FakeEngineRequest request)? beforeAdmin;

  Duration tokenDelay = Duration.zero;

  /// A chat with this HTTP status as its answer, before any reading.
  int? Function(List<String> prompt)? chatStatusFor;

  // What a test reads.
  List<String> live = [];
  late final List<FakeEngineSlot> slots = [
    for (var i = 0; i < slotCount; i++) FakeEngineSlot(),
  ];
  final List<FakeEngineRequest> log = [];

  /// Every request in the order it reached the socket, before it waited for
  /// the generation lock. [log] is the order the lock served them.
  final List<FakeEngineRequest> arrived = [];

  /// Aborts the engine was asked for, and when it was asked how busy it is.
  int aborts = 0;
  final List<DateTime> perfAsks = [];

  /// Requests that have reached the socket and not been answered yet.
  int inFlight = 0;
  int maxInFlight = 0;

  /// Chats and admin calls, by kind.
  Iterable<FakeEngineRequest> of(String kind) =>
      log.where((r) => r.kind == kind);
  List<String> get kinds => [for (final r in log) r.kind];

  void forgetLog() {
    log.clear();
    arrived.clear();
    aborts = 0;
  }

  Future<void> _lock = Future<void>.value();

  /// Waits its turn behind every earlier request, like KoboldCpp's lock.
  Future<void> _locked(Future<void> Function() body) {
    final done = Completer<void>();
    final turn = _lock;
    _lock = done.future;
    return turn.then((_) async {
      try {
        await body();
      } finally {
        done.complete();
      }
    });
  }

  static List<String> words(String text) =>
      text.trim().isEmpty ? [] : text.trim().split(RegExp(r'\s+'));

  static List<String> promptOf(Object? messages) {
    final out = <String>[];
    for (final m in (messages as List).cast<Map>()) {
      out.add('<${m['role']}>');
      final content = m['content'];
      if (content is String) {
        out.addAll(words(content));
      } else if (content is List) {
        for (final part in content.cast<Map>()) {
          if (part['text'] is String) out.addAll(words(part['text'] as String));
        }
      }
    }
    return out;
  }

  void _serve() => _server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    Map<String, dynamic> json = {};
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) json = decoded;
    } on FormatException {
      // an empty body is fine
    }
    final path = req.uri.path;
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    try {
      switch (path) {
        case '/v1/chat/completions':
          await _chat(req, json);
        case '/api/admin/check_state':
        case '/api/admin/load_state':
        case '/api/admin/save_state':
        case '/api/admin/clear_state':
          await _admin(req, path.split('/').last.split('_').first, json);
        case '/api/extra/perf':
          // Busy: an idle unload that asks stops there.
          perfAsks.add(DateTime.now());
          await _reply(req, {'uptime': 5.0, 'idle': 0, 'queue': 0});
        case '/api/extra/abort':
          aborts++;
          await _reply(req, {'success': 'true', 'done': 'true'});
        case '/api/extra/version':
          await _reply(req, {'result': 'KoboldCpp', 'version': '1.122.1'});
        case '/api/extra/tokencount':
          await _reply(req, {
            'value': words(json['prompt']?.toString() ?? '').length,
          });
        default:
          await _reply(req, {'detail': 'not found'}, status: 404);
      }
    } finally {
      inFlight--;
    }
  });

  Future<void> _reply(HttpRequest req, Object body, {int status = 200}) async {
    try {
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(body));
      // A client that left can make this never return.
      await req.response.close().timeout(const Duration(seconds: 1));
    } on Object {
      // the client left
    }
  }

  Future<void> _admin(
    HttpRequest req,
    String verb,
    Map<String, dynamic> json,
  ) async {
    final raw = json['slot'];
    var slot = raw is num ? raw.toInt() : 0;
    if (slot < 0 || slot >= slotCount) slot = 0;
    final entry = FakeEngineRequest(verb, slot: verb == 'check' ? null : slot);
    arrived.add(entry);
    if (verb == 'load' && loadStatus != null) {
      await _locked(() async => log.add(entry..ok = false));
      return _reply(req, {'detail': 'busy'}, status: loadStatus!);
    }
    late Map<String, Object?> answer;
    await _locked(() async {
      log.add(entry);
      await beforeAdmin?.call(entry);
      answer = _adminAnswer(verb, slot, entry);
      entry.endedAt = DateTime.now();
    });
    return _reply(req, answer);
  }

  Map<String, Object?> _adminAnswer(
    String verb,
    int slot,
    FakeEngineRequest entry,
  ) {
    Map<String, Object?> no(Map<String, Object?> shape) {
      entry.ok = false;
      return {'success': false, ...shape};
    }

    if (!adminOn) {
      return switch (verb) {
        'check' => no({'old_states': [], 'new_state_size': 0, 'new_tokens': 0}),
        'save' => no({'new_state_size': 0, 'new_tokens': 0}),
        'load' => no({'new_tokens': 0}),
        _ => no({}),
      };
    }
    switch (verb) {
      case 'check':
        return {
          'success': true,
          'old_states': [
            for (final s in slots) {'tokens': s.tokens.length, 'size': s.bytes},
          ],
          'new_state_size': live.length * bytesPerToken,
          'new_tokens': live.length,
        };
      case 'save':
        if (failSaves) {
          return no({'new_state_size': 0, 'new_tokens': live.length});
        }
        final s = slots[slot];
        s.tokens = List.of(live);
        s.bytes = live.length * bytesPerToken;
        return {
          'success': s.bytes > 0,
          'new_state_size': s.bytes,
          'new_tokens': live.length,
        };
      case 'load':
        final s = slots[slot];
        if (failLoads || s.tokens.isEmpty) {
          return no({'new_tokens': live.length});
        }
        live = List.of(s.tokens);
        return {'success': true, 'new_tokens': live.length};
      default:
        if (failClears) return no({});
        for (final s in slots) {
          s.tokens = [];
          s.bytes = 0;
        }
        return {'success': true};
    }
  }

  /// Writes one event. False when the client has left: a closed connection
  /// makes dart:io's flush throw or never return, so a short wait is the
  /// only way to tell.
  Future<bool> _push(HttpResponse response, String data) async {
    try {
      response.write(data);
      await response.flush().timeout(const Duration(milliseconds: 400));
      return true;
    } on Object {
      return false;
    }
  }

  Future<void> _chat(HttpRequest req, Map<String, dynamic> json) async {
    final stream = json['stream'] == true;
    final prompt = promptOf(json['messages']);
    final entry = FakeEngineRequest('chat')
      ..prompt = prompt
      ..stream = stream
      ..hadTools = json['tools'] != null;
    arrived.add(entry);
    final status = chatStatusFor?.call(prompt);
    if (status != null) {
      return _reply(req, {'detail': 'error'}, status: status);
    }
    await _locked(() async {
      log.add(entry);
      var common = 0;
      while (common < live.length &&
          common < prompt.length &&
          live[common] == prompt[common]) {
        common++;
      }
      entry.processed = prompt.length - common;
      live = [...prompt];
      final hold = beforeReply;
      if (hold != null) await hold(entry);
      final reply = [for (var i = 0; i < replyWords; i++) 'r${log.length}_$i'];
      if (stream) {
        req.response.statusCode = 200;
        req.response.bufferOutput = false;
        req.response.headers.set('Content-Type', 'text/event-stream');
        for (final word in reply) {
          if (tokenDelay > Duration.zero) {
            await Future<void>.delayed(tokenDelay);
          }
          final event = jsonEncode({
            'choices': [
              {
                'delta': {'content': '$word '},
              },
            ],
          });
          if (!await _push(req.response, 'data: $event\n\n')) {
            entry.cutShort = true;
            break;
          }
          live.add(word);
          entry.replyTokens++;
        }
        if (!entry.cutShort && await _push(req.response, 'data: [DONE]\n\n')) {
          unawaited(req.response.close().then((_) {}, onError: (_) {}));
        }
      } else {
        live.addAll(reply);
        entry.replyTokens = reply.length;
        await _reply(req, {
          'choices': [
            {
              'message': {'role': 'assistant', 'content': reply.join(' ')},
              'finish_reason': 'stop',
            },
          ],
          'usage': {
            'prompt_tokens': prompt.length,
            'completion_tokens': reply.length,
          },
        });
      }
    });
  }
}
