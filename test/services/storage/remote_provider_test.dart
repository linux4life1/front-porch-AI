// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/services/storage/settings/remote_provider.dart';

void main() {
  group('resolveRemoteProviderKind', () {
    test('kobold backend wins over a leftover URL', () {
      expect(
        resolveRemoteProviderKind(backendType: 'kobold', url: kOpenRouterApiV1),
        RemoteProviderKind.kobold,
      );
    });

    test('omlx backend is oMLX even if the saved URL is OpenRouter', () {
      expect(
        resolveRemoteProviderKind(backendType: 'omlx', url: kOpenRouterApiV1),
        RemoteProviderKind.omlx,
      );
    });

    test('named OpenAI hosts by URL', () {
      expect(
        resolveRemoteProviderKind(
          backendType: 'openRouter',
          url: kOpenRouterApiV1,
        ),
        RemoteProviderKind.openRouter,
      );
      expect(
        resolveRemoteProviderKind(
          backendType: 'openRouter',
          url: kNanoGptApiV1,
        ),
        RemoteProviderKind.nanoGpt,
      );
      expect(
        resolveRemoteProviderKind(
          backendType: 'openRouter',
          url: kLmStudioApiV1,
        ),
        RemoteProviderKind.lmStudio,
      );
      expect(
        resolveRemoteProviderKind(
          backendType: 'openRouter',
          url: 'http://127.0.0.1:1234/v1',
        ),
        RemoteProviderKind.lmStudio,
      );
    });

    test('anything else is Custom', () {
      expect(
        resolveRemoteProviderKind(
          backendType: 'openRouter',
          url: 'http://192.168.1.10:8080/v1',
        ),
        RemoteProviderKind.custom,
      );
      expect(
        resolveRemoteProviderKind(backendType: 'openRouter', url: ''),
        RemoteProviderKind.custom,
      );
    });
  });

  group('remoteApiUrlIsLmStudio', () {
    test('localhost and 127.0.0.1 port 1234', () {
      expect(remoteApiUrlIsLmStudio(kLmStudioApiV1), isTrue);
      expect(remoteApiUrlIsLmStudio('http://127.0.0.1:1234/v1/'), isTrue);
      expect(remoteApiUrlIsLmStudio('http://localhost:8000/v1'), isFalse);
      expect(remoteApiUrlIsLmStudio(kOpenRouterApiV1), isFalse);
    });
  });
}
