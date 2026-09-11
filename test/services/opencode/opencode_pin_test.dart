// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';

void main() {
  test('pins a known-good 1.18.x and never latest', () {
    expect(kOpenCodePinnedVersion, startsWith('1.18.'));
    expect(kOpenCodePinnedVersion, isNot(contains('latest')));
  });

  test('GitHub asset names match Mac zip, Linux tar.gz, Windows zip', () {
    expect(
      openCodeReleaseAssetName(os: 'darwin', arch: 'arm64'),
      'opencode-darwin-arm64.zip',
    );
    expect(
      openCodeReleaseAssetName(os: 'darwin', arch: 'x64'),
      'opencode-darwin-x64.zip',
    );
    expect(
      openCodeReleaseAssetName(os: 'linux', arch: 'x64'),
      'opencode-linux-x64.tar.gz',
    );
    expect(
      openCodeReleaseAssetName(os: 'linux', arch: 'arm64'),
      'opencode-linux-arm64.tar.gz',
    );
    expect(
      openCodeReleaseAssetName(os: 'windows', arch: 'x64'),
      'opencode-windows-x64.zip',
    );
    expect(
      openCodeReleaseAssetName(os: 'windows', arch: 'arm64'),
      'opencode-windows-arm64.zip',
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
    expect(
      openCodeDownloadUrl(
        version: kOpenCodePinnedVersion,
        os: 'linux',
        arch: 'x64',
      ),
      endsWith('opencode-linux-x64.tar.gz'),
    );
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

  test('honesty names pin vs disk vs GitHub and never brew', () {
    expect(
      openCodeUpgradeHonesty(installed: null, pinned: '1.18.30'),
      contains('not in the closet'),
    );
    expect(
      openCodeUpgradeHonesty(
        installed: '1.0.0',
        pinned: '1.18.30',
        remote: '1.19.0',
      ),
      contains('1.0.0 → 1.18.30'),
    );
    expect(
      openCodeUpgradeHonesty(
        installed: '1.0.0',
        pinned: '1.18.30',
        remote: '1.19.0',
      ),
      contains('GitHub latest is 1.19.0'),
    );
    expect(
      openCodeUpgradeHonesty(installed: '1.18.30', pinned: '1.18.30'),
      contains('current (pin)'),
    );
    expect(
      openCodeUpgradeButtonLabel(installed: null, pinned: '1.18.30'),
      contains('Download 1.18.30'),
    );
    expect(
      openCodeUpgradeButtonLabel(installed: '1.18.30', pinned: '1.18.30'),
      'Up to date',
    );
  });
}
