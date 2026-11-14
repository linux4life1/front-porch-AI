// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The settings snapshot is the PWA's only read of host state. This pins the
// two keys PR 7b adds to it: the `appearance` block (the Appearance tab's
// picks and catalogs) and `autoCheckForUpdates` (General's update switch),
// the latter only on a host that actually has an update service.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/settings/settings.dart';

import '../../golden/support/creator_test_support.dart';
import '../../golden/support/fakes.dart';

/// The snapshot also reads the remote lane's reachability label; the shared
/// fake leaves it out, so give this test a real (unconfigured) service.
class _FakeLlm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();

  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  test('the snapshot mounts the appearance wire beside the theme', () async {
    setupPathProviderMock();
    final storage = await makeGoldenStorage();
    final llm = _FakeLlm();
    final snap = SettingsSnapshot(
      storage,
      llm,
      SettingsReasoning(storage, llm),
    );

    final data = snap.build();
    expect(data['theme'], isA<Map>());
    final appearance = data['appearance'] as Map<String, Object?>;
    expect(appearance['themeId'], 'porch');
    expect(appearance['uiFont'], 'inter');
    expect(appearance['corners'], 'default');
    expect(appearance['gallery'], hasLength(8));
    expect(appearance['accentSwatches'], hasLength(12));
  });

  test('auto-check rides the snapshot only with an update service', () async {
    setupPathProviderMock();
    final storage = await makeGoldenStorage();
    final llm = _FakeLlm();
    final reasoning = SettingsReasoning(storage, llm);

    expect(
      SettingsSnapshot(
        storage,
        llm,
        reasoning,
      ).build().containsKey('autoCheckForUpdates'),
      isFalse,
      reason: 'a partial host shows no row instead of a dead switch',
    );

    final update = UpdateService();
    final snap = SettingsSnapshot(storage, llm, reasoning, update: update);
    expect(snap.build()['autoCheckForUpdates'], isTrue);
    await update.setAutoCheckEnabled(false);
    expect(snap.build()['autoCheckForUpdates'], isFalse);
  });
}
