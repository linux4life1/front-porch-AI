// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart' show Response;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/web/routes/civitai_routes.dart';

import 'civitai_route_support.dart';

void main() {
  late Map<String, String> box;
  late CivitaiAuthHarness harness;
  var adult = false;

  Future<CivitaiRoutes> routes({CivitaiCredentialStore? store}) async {
    harness = await CivitaiAuthHarness.create();
    return CivitaiRoutes(
      Router(),
      auth: harness.auth,
      adultAllowed: () => adult,
      relay: CivitaiRelay(store ?? memoryCivitaiStore(box)),
    );
  }

  setUp(() {
    box = {};
    adult = false;
  });

  group('saving the key from the phone needs the password', () {
    test('a session alone cannot store a key', () async {
      final r = await routes();
      final res = await r.saveCredential(
        civitaiRequest(
          'POST',
          '/api/image/civitai/credential',
          body: {'token': 'stolen-session-token'},
        ),
      );
      expect(res.statusCode, 401);
      expect(box, isEmpty);
    });

    test('a wrong password stores nothing', () async {
      final r = await routes();
      final res = await r.saveCredential(
        civitaiRequest(
          'POST',
          '/api/image/civitai/credential',
          body: {'token': 't', 'currentPassword': 'not-the-password'},
        ),
      );
      expect(res.statusCode, 401);
      expect(box, isEmpty);
    });

    test('the right password stores the key for the cookie account', () async {
      final r = await routes();
      final res = await r.saveCredential(
        civitaiRequest(
          'POST',
          '/api/image/civitai/credential',
          body: {'token': ' t ', 'currentPassword': kCivitaiTestPassword},
        ),
      );
      expect(res.statusCode, 200);
      expect(box, {'civitai_credential_local': 't'});
    });

    test('a password field is not a CivitAI key', () async {
      final r = await routes();
      final res = await r.saveCredential(
        civitaiRequest(
          'POST',
          '/api/image/civitai/credential',
          body: {
            'password': 'hunter2',
            'token': 't',
            'currentPassword': kCivitaiTestPassword,
          },
        ),
      );
      expect(res.statusCode, 400);
      expect((await civitaiJson(res))['code'], 'bad_request');
      expect(box, isEmpty);
    });

    test('a "red" flag no longer writes a second key', () async {
      final r = await routes();
      await r.saveCredential(
        civitaiRequest(
          'POST',
          '/api/image/civitai/credential',
          body: {
            'token': 't',
            'red': true,
            'currentPassword': kCivitaiTestPassword,
          },
        ),
      );
      expect(box.keys, ['civitai_credential_local']);
    });
  });

  group('deleting the key from the phone needs the password', () {
    test('a session alone cannot delete it', () async {
      box['civitai_credential_local'] = 'keep-me';
      final r = await routes();
      final res = await r.signOut(
        civitaiRequest('DELETE', '/api/image/civitai/credential'),
      );
      expect(res.statusCode, 401);
      expect(box['civitai_credential_local'], 'keep-me');
    });

    test('the right password deletes it', () async {
      box['civitai_credential_local'] = 'gone';
      final r = await routes();
      final res = await r.signOut(
        civitaiRequest(
          'DELETE',
          '/api/image/civitai/credential',
          body: {'currentPassword': kCivitaiTestPassword},
        ),
      );
      expect(res.statusCode, 200);
      expect(box, isEmpty);
    });
  });

  group(
    'with two-factor on, the key needs the code as well as the password',
    () {
      late CivitaiRoutes twoFactor;
      late CivitaiAuthHarness auth;

      Future<void> arrange() async {
        auth = await CivitaiAuthHarness.create();
        await auth.enableTwoFactor();
        twoFactor = CivitaiRoutes(
          Router(),
          auth: auth.auth,
          adultAllowed: () => adult,
          relay: CivitaiRelay(memoryCivitaiStore(box)),
        );
      }

      Future<Response> save(Map<String, Object?> extra) =>
          twoFactor.saveCredential(
            civitaiRequest(
              'POST',
              '/api/image/civitai/credential',
              body: {'token': 'new-key', ...extra},
            ),
          );

      Future<Response> remove(Map<String, Object?> extra) => twoFactor.signOut(
        civitaiRequest('DELETE', '/api/image/civitai/credential', body: extra),
      );

      test(
        'saving with only the password is refused and asks for the code',
        () async {
          await arrange();
          final res = await save({'currentPassword': kCivitaiTestPassword});
          expect(res.statusCode, 401);
          final json = await civitaiJson(res);
          expect(json['totpRequired'], isTrue);
          expect(box, isEmpty);
        },
      );

      test('saving with a wrong code is refused', () async {
        await arrange();
        final res = await save({
          'currentPassword': kCivitaiTestPassword,
          'totpCode': auth.code(monthsAway: 12),
        });
        expect(res.statusCode, 401);
        expect(box, isEmpty);
      });

      test(
        'saving with the password and the right code stores the key',
        () async {
          await arrange();
          final res = await save({
            'currentPassword': kCivitaiTestPassword,
            'totpCode': auth.code(),
          });
          expect(res.statusCode, 200);
          expect(box, {'civitai_credential_local': 'new-key'});
        },
      );

      test('the code alone, with a wrong password, is not enough', () async {
        await arrange();
        final res = await save({
          'currentPassword': 'not-the-password',
          'totpCode': auth.code(),
        });
        expect(res.statusCode, 401);
        expect(box, isEmpty);
      });

      test(
        'deleting with only the password is refused, and the key stays',
        () async {
          await arrange();
          box['civitai_credential_local'] = 'keep-me';
          final res = await remove({'currentPassword': kCivitaiTestPassword});
          expect(res.statusCode, 401);
          expect((await civitaiJson(res))['totpRequired'], isTrue);
          expect(box['civitai_credential_local'], 'keep-me');
        },
      );

      test(
        'deleting with a wrong code is refused, and the key stays',
        () async {
          await arrange();
          box['civitai_credential_local'] = 'keep-me';
          final res = await remove({
            'currentPassword': kCivitaiTestPassword,
            'totpCode': auth.code(monthsAway: 12),
          });
          expect(res.statusCode, 401);
          expect(box['civitai_credential_local'], 'keep-me');
        },
      );

      test(
        'deleting with the password and the right code removes it',
        () async {
          await arrange();
          box['civitai_credential_local'] = 'gone';
          final res = await remove({
            'currentPassword': kCivitaiTestPassword,
            'totpCode': auth.code(),
          });
          expect(res.statusCode, 200);
          expect(box, isEmpty);
        },
      );
    },
  );

  group('adult results follow the app setting on the server', () {
    test('adult search is refused while adult themes are off', () async {
      box['civitai_credential_local'] = 'key';
      final r = await routes();
      final res = await r.search(
        civitaiRequest('GET', '/api/image/civitai/search?q=x&adult=true'),
      );
      expect(res.statusCode, 403);
      final body = await civitaiJson(res);
      expect(body['code'], 'adult_disabled');
      expect(body.containsKey('items'), isFalse);
    });

    test('adult search with the setting on still needs a key', () async {
      adult = true;
      final r = await routes();
      final res = await r.search(
        civitaiRequest('GET', '/api/image/civitai/search?q=x&adult=true'),
      );
      expect(res.statusCode, 200);
      final body = await civitaiJson(res);
      expect(body['needsCredential'], isTrue);
      expect(body['items'], isEmpty);
    });

    test('an adult download is refused while adult themes are off', () async {
      box['civitai_credential_local'] = 'key';
      final r = await routes();
      final res = await r.download(
        civitaiRequest(
          'POST',
          '/api/image/civitai/download',
          body: {'versionId': 1, 'adult': true, 'backend': 'comfyui'},
        ),
      );
      expect(res.statusCode, 403);
      expect((await civitaiJson(res))['code'], 'adult_disabled');
    });
  });

  group('the key store', () {
    CivitaiCredentialStore broken() => CivitaiCredentialStore(
      readKey: (_) async => throw StateError('keychain locked'),
      writeKey: (_, _) async => throw StateError('keychain locked'),
      deleteKey: (_) async => throw StateError('keychain locked'),
    );

    test('a store that cannot be read is an error, not "no key"', () async {
      final r = await routes(store: broken());
      final res = await r.credentialStatus(
        civitaiRequest('GET', '/api/image/civitai/credential'),
      );
      expect(res.statusCode, 503);
      expect((await civitaiJson(res))['code'], 'key_store');
    });

    test('a store that cannot be written says so after the password', () async {
      final r = await routes(store: broken());
      final res = await r.saveCredential(
        civitaiRequest(
          'POST',
          '/api/image/civitai/credential',
          body: {'token': 't', 'currentPassword': kCivitaiTestPassword},
        ),
      );
      expect(res.statusCode, 503);
      expect((await civitaiJson(res))['code'], 'key_store');
    });

    test('credential status reports only whether a key is saved', () async {
      box['civitai_credential_local'] = 'secret';
      final r = await routes();
      final res = await r.credentialStatus(
        civitaiRequest('GET', '/api/image/civitai/credential'),
      );
      final body = await civitaiJson(res);
      expect(body, {'saved': true});
    });
  });
}
