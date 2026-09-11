// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';

void main() {
  test('pins a known-good 1.18.x and never latest', () {
    expect(kOpenCodePinnedVersion, startsWith('1.18.'));
    expect(kOpenCodePinnedVersion, isNot(contains('latest')));
  });

  test('GitHub asset names match the published zip layout', () {
    expect(
      openCodeReleaseAssetName(os: 'darwin', arch: 'arm64'),
      'opencode-darwin-arm64.zip',
    );
    expect(
      openCodeReleaseAssetName(os: 'linux', arch: 'x64'),
      'opencode-linux-x64.zip',
    );
    expect(
      openCodeReleaseAssetName(os: 'windows', arch: 'x64'),
      'opencode-windows-x64.zip',
    );
  });

  test('download URL is the pinned GitHub release, not brew', () {
    final url = openCodeDownloadUrl(
      version: kOpenCodePinnedVersion,
      os: 'darwin',
      arch: 'arm64',
    );
    expect(url, contains('/anomalyco/opencode/releases/download/'));
    expect(url, contains('v$kOpenCodePinnedVersion/'));
    expect(url, endsWith('opencode-darwin-arm64.zip'));
    expect(url, isNot(contains('homebrew')));
  });

  test('brew and user-config paths are rejected as the product copy', () {
    expect(openCodeLooksLikeBrewPath('/opt/homebrew/bin/opencode'), isTrue);
    expect(openCodeLooksLikeBrewPath('/usr/local/bin/opencode'), isTrue);
    expect(
      openCodeLooksLikeUserConfigPath(
        '/Users/sam/.config/opencode/opencode.json',
      ),
      isTrue,
    );
    expect(
      openCodeLooksLikeBrewPath('/tmp/FrontPorchAI/opencode-bin/opencode'),
      isFalse,
    );
  });
}
