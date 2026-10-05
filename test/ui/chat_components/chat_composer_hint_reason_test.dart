// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The chat composer's placeholder says why the app's start of KoboldCpp was
// refused, in place of "No API connection", for as long as there is no
// connection. A connected composer never shows it, so a refusal that has been
// overtaken cannot stay on screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/ui/chat_components/chat_composer_hint.dart';

void main() {
  const reason =
      'Not a valid GGUF model file: the file is probably a partial download.';

  test('with no connection the reason is the hint', () {
    expect(
      chatComposerHint(apiReady: false, observerMode: false, reason: reason),
      reason,
    );
  });

  test('observer mode does not hide it', () {
    expect(
      chatComposerHint(apiReady: false, observerMode: true, reason: reason),
      reason,
    );
  });

  test('with no reason the hint is the generic one', () {
    expect(
      chatComposerHint(apiReady: false, observerMode: false),
      kNoApiConnectionHint,
    );
  });

  test('a connection ignores the reason', () {
    expect(
      chatComposerHint(apiReady: true, observerMode: false, reason: reason),
      kTypeAMessageHint,
    );
    expect(
      chatComposerHint(apiReady: true, observerMode: true, reason: reason),
      kDirectTheSceneHint,
    );
  });
}
