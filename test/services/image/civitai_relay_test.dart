import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_client.dart';
import 'package:front_porch_ai/services/web/middleware/auth_middleware.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

void main() {
  CivitaiCredentialStore memory(Map<String, String> box) {
    return CivitaiCredentialStore(
      readKey: (key) async => box[key],
      writeKey: (key, value) async {
        box[key] = value;
      },
      deleteKey: (key) async {
        box.remove(key);
      },
    );
  }

  test(
    'a pasted key is stored per account and sign-out removes only that one',
    () async {
      final box = <String, String>{};
      final store = memory(box);
      await store.save('local', 'token-a');
      await store.save('other', 'token-b');
      expect(box['civitai_credential_local'], 'token-a');
      expect(await store.read('other'), 'token-b');
      await store.signOut('local');
      expect(await store.read('local'), isNull);
      expect(await store.read('other'), 'token-b');
      expect(() => store.save('local', '   '), throwsArgumentError);
    },
  );

  test('a password is not a CivitAI key', () {
    expect(pastedCivitaiToken({'password': 'secret'}), isNull);
    expect(pastedCivitaiToken({'token': '  abc  '}), 'abc');
    expect(pastedCivitaiToken({'token': '   '}), isNull);
  });

  test('adult search needs a credential and stays off the query string', () {
    expect(
      civitaiModelsUri(
        query: 'pony',
        adult: true,
        hasCredential: false,
        lora: false,
      ),
      isNull,
    );
    final adult = civitaiModelsUri(
      query: 'pony',
      adult: true,
      hasCredential: true,
      lora: true,
    )!;
    expect(adult.host, 'civitai.red');
    expect(adult.queryParameters['nsfw'], 'true');
    expect(adult.queryParameters.containsKey('browsingLevel'), isFalse);
    expect(adult.queryParameters['types'], 'LORA');
    expect(adult.toString().contains('token'), isFalse);
    final pg = civitaiModelsUri(
      query: 'portrait',
      adult: false,
      hasCredential: false,
      lora: false,
    )!;
    expect(pg.host, 'civitai.com');
    expect(pg.queryParameters.containsKey('nsfw'), isFalse);
  });

  test('adult rows are hidden until the account has a credential', () {
    const body =
        '{"items":['
        '{"id":1,"name":"Day","type":"Checkpoint","nsfw":false,'
        '"modelVersions":[{"id":10,"files":[{"name":"day.safetensors"}]}]},'
        '{"id":2,"name":"Night","type":"LORA","nsfw":true,'
        '"modelVersions":[{"id":20,"files":[{"name":"night.safetensors"}]}]}'
        ']}';
    final pg = parseCivitaiModels(body, includeAdult: false);
    expect(pg.map((row) => row.name), ['Day']);
    final all = parseCivitaiModels(body, includeAdult: true);
    expect(all.map((row) => row.name), ['Day', 'Night']);
    expect(all.last.versionId, 20);
    expect(all.last.filename, 'night.safetensors');
    expect(parseCivitaiModels('not json', includeAdult: true), isEmpty);
  });

  test('the relay uses the cookie account and does not log the key', () async {
    final box = <String, String>{};
    final store = memory(box);
    await store.save('local', 'super-secret-token');
    await store.save('other', 'other-secret-token');
    final relay = CivitaiRelay(store);
    expect(civitaiRelayAccount('local'), 'local');
    expect(civitaiRelayAccount('  '), isNull);
    final search = await relay.planSearch(
      accountId: 'local',
      query: 'pony',
      adult: true,
      lora: false,
    );
    expect(search.authorization, 'Bearer super-secret-token');
    expect(search.log.contains('super-secret-token'), isFalse);
    expect(search.uri.toString().contains('super-secret-token'), isFalse);
    final escaped = await relay.planDownload(
      accountId: 'local',
      versionId: 10,
      adult: false,
      savedRoot: '/models',
      filename: '../../x.safetensors',
      civitaiType: 'Checkpoint',
      fromLoraSheet: false,
      backend: 'comfyui',
    );
    expect(escaped.refused, isTrue);
    expect(escaped.path, isNull);
    expect(escaped.log.contains('super-secret-token'), isFalse);
    final wrongSheet = await relay.planDownload(
      accountId: 'other',
      versionId: 20,
      adult: false,
      savedRoot: '/models',
      filename: 'style.safetensors',
      civitaiType: 'LORA',
      fromLoraSheet: false,
      backend: 'comfyui',
    );
    expect(wrongSheet.refused, isTrue);
    final saved = await relay.planDownload(
      accountId: 'other',
      versionId: 20,
      adult: false,
      savedRoot: '/models',
      filename: 'style.safetensors',
      civitaiType: 'LORA',
      fromLoraSheet: true,
      backend: 'comfyui',
    );
    expect(saved.path, p.join('/models', 'loras', 'style.safetensors'));
    expect(saved.authorization, 'Bearer other-secret-token');
    expect(saved.uri.toString().contains('other-secret-token'), isFalse);
    expect(saved.log.contains('other-secret-token'), isFalse);
  });

  test('a redirect to another host drops the CivitAI key', () {
    const token = 'Bearer super-secret-token';
    final same = civitaiFollowHeaders(
      from: Uri.parse('https://civitai.com/api/download/models/1'),
      to: Uri.parse('https://civitai.com/api/download/models/1'),
      authorization: token,
    );
    expect(same['Authorization'], token);
    final away = civitaiFollowHeaders(
      from: Uri.parse('https://civitai.com/api/download/models/1'),
      to: Uri.parse('https://cdn.example/file.safetensors'),
      authorization: token,
    );
    expect(away, isEmpty);
  });

  test('a locked file is reported and a missing key is not a success', () {
    expect(civitaiHttpKind(401), CivitaiHttpKind.needsCredential);
    expect(civitaiHttpKind(403), CivitaiHttpKind.locked);
    expect(civitaiHttpKind(200), CivitaiHttpKind.ok);
  });

  Request post(String path, Map<String, Object?> body, {String? account}) {
    return Request(
      'POST',
      Uri.parse('http://localhost$path'),
      body: jsonEncode(body),
      context: {kAuthUserIdContextKey: ?account},
    );
  }

  test(
    'the credential route stores the cookie account, not the body',
    () async {
      final box = <String, String>{};
      final store = memory(box);
      await store.save('other', 'keep');
      final routes = CivitaiRoutes(Router(), relay: CivitaiRelay(store));
      final saved = await routes.saveCredential(
        post('/api/image/civitai/credential', {
          'accountId': 'other',
          'token': 't',
        }, account: 'local'),
      );
      expect(saved.statusCode, 200);
      expect(box['civitai_credential_local'], 't');
      expect(box['civitai_credential_other'], 'keep');
      final gone = await routes.signOut(
        Request(
          'DELETE',
          Uri.parse('http://localhost/api/image/civitai/credential'),
          body: jsonEncode({'accountId': 'other'}),
          context: {kAuthUserIdContextKey: 'local'},
        ),
      );
      expect(gone.statusCode, 200);
      expect(box.containsKey('civitai_credential_local'), isFalse);
      expect(box['civitai_credential_other'], 'keep');
      final denied = await routes.signOut(
        Request(
          'DELETE',
          Uri.parse('http://localhost/api/image/civitai/credential'),
          body: jsonEncode({'accountId': 'other'}),
        ),
      );
      expect(denied.statusCode, 401);
      expect(box['civitai_credential_other'], 'keep');
    },
  );

  test('the phone cannot choose the models folder', () async {
    final box = <String, String>{};
    final store = memory(box);
    await store.save('local', 'super-secret-token');
    final routes = CivitaiRoutes(
      Router(),
      relay: CivitaiRelay(store),
      rootFor: (backend) => backend == 'comfyui' ? '/models' : null,
    );
    final response = await routes.download(
      post('/api/image/civitai/download', {
        'accountId': 'other',
        'versionId': 20,
        'root': '/tmp/evil',
        'filename': 'style.safetensors',
        'type': 'LORA',
        'lora': true,
        'backend': 'comfyui',
      }, account: 'local'),
    );
    expect(response.statusCode, 501);
    final body = jsonDecode(await response.readAsString()) as Map;
    expect(body['downloaded'], isFalse);
    expect(body['path'], p.join('/models', 'loras', 'style.safetensors'));
    expect(body.toString().contains('super-secret-token'), isFalse);
    expect(body.toString().contains('/tmp/evil'), isFalse);
    final missing = await routes.download(
      post('/api/image/civitai/download', {
        'versionId': 20,
        'root': '/tmp/evil',
        'filename': 'style.safetensors',
        'type': 'LORA',
        'lora': true,
        'backend': 'drawthings',
      }, account: 'local'),
    );
    expect(missing.statusCode, 400);
    final missingBody = jsonDecode(await missing.readAsString()) as Map;
    expect(
      missingBody['error'],
      'Draw Things models folder was not found on this Mac',
    );
  });
}
