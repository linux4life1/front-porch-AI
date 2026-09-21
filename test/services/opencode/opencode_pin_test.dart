// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/opencode/opencode.dart';

void main() {
  test('latest download URL is GitHub latest, not brew', () {
    final url = openCodeLatestDownloadUri(os: 'darwin', arch: 'arm64');
    expect(
      url.toString(),
      'https://github.com/anomalyco/opencode/releases/latest/download/'
      'opencode-darwin-arm64.zip',
    );
    expect(url.toString(), isNot(contains('homebrew')));
    expect(
      openCodeLatestDownloadUri(os: 'linux', arch: 'x64').toString(),
      endsWith('opencode-linux-x64.tar.gz'),
    );
    expect(
      openCodeLatestDownloadUri(os: 'linux', arch: 'x64').toString(),
      contains('/releases/latest/download/'),
    );
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

  test('versioned download URL still names a tag asset', () {
    final url = openCodeDownloadUrl(
      version: '1.19.99',
      os: 'darwin',
      arch: 'arm64',
    );
    expect(url, contains('/anomalyco/opencode/releases/download/'));
    expect(url, contains('v1.19.99/'));
    expect(url, endsWith('opencode-darwin-arm64.zip'));
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

  test('honesty names disk vs GitHub latest and never brew', () {
    expect(
      openCodeUpgradeHonesty(installed: null),
      contains('not in the closet'),
    );
    expect(
      openCodeUpgradeHonesty(installed: '1.0.0', remote: '1.19.0'),
      contains('1.0.0 → 1.19.0'),
    );
    expect(
      openCodeUpgradeHonesty(installed: '1.19.0', remote: '1.19.0'),
      contains('is current'),
    );
    expect(openCodeUpgradeButtonLabel(installed: null), 'Download');
    expect(
      openCodeUpgradeButtonLabel(installed: '1.18.30', remote: null),
      'Check for Updates',
    );
    expect(
      openCodeUpgradeButtonLabel(
        installed: '1.18.30',
        versionError: 'Could not check GitHub',
      ),
      'Check (failed)',
    );
    expect(
      openCodeUpgradeButtonLabel(installed: '1.18.30', remote: '1.19.0'),
      'Update to v1.19.0',
    );
    expect(
      openCodeUpgradeButtonLabel(installed: '1.19.0', remote: '1.19.0'),
      'Up to date',
    );
  });
}
