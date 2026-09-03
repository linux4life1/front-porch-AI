// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// POST /api/image/config only stepped up for remoteApiUrl/apiKey. Changing
// localUrl / comfyUrl / drawThingsHost from a stolen session cookie would
// redirect generation. Same class of SSRF as the remote URL.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/web/util/step_up.dart';

void main() {
  const current = (
    remote: 'https://openrouter.ai/api/v1',
    local: 'http://127.0.0.1:7860',
    comfy: 'http://127.0.0.1:8188',
    dt: '127.0.0.1',
  );

  bool check(Map<String, dynamic> body) => imageConfigWriteNeedsStepUp(
    body,
    currentRemoteApiUrl: current.remote,
    currentLocalUrl: current.local,
    currentComfyUrl: current.comfy,
    currentDrawThingsHost: current.dt,
  );

  test('unchanged hosts do not need step-up', () {
    expect(check({'localUrl': current.local, 'steps': 20}), isFalse);
    expect(check({'style': 'anime'}), isFalse);
  });

  test('a new A1111 URL needs step-up', () {
    expect(check({'localUrl': 'http://evil.example:7860'}), isTrue);
  });

  test('a new Comfy URL needs step-up', () {
    expect(check({'comfyUrl': 'http://evil.example:8188'}), isTrue);
  });

  test('a new Draw Things host needs step-up', () {
    expect(check({'drawThingsHost': 'evil.example'}), isTrue);
  });

  test('a new remote URL still needs step-up', () {
    expect(check({'remoteApiUrl': 'https://evil.example/v1'}), isTrue);
  });
}
