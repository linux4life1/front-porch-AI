// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/update_service.dart';

// Regression coverage for the nightly update-ordering bug: the updater used to
// take the FIRST channel-matching release GitHub returned and stop. Because the
// Rawhide version string (rawhide.YYYYMMDD.<sha>) has no orderable field below
// the day and GitHub's list order is not reliably newest-first, a newer
// same-day manual build listed below an older release was never offered.
// selectTargetRelease must instead pick the channel match with the newest
// publish timestamp, and keep stable/nightly strictly isolated.
Map<String, dynamic> _rel({
  required String tag,
  required bool prerelease,
  String? publishedAt,
  String? createdAt,
}) => {
  'tag_name': tag,
  'prerelease': prerelease,
  'published_at': publishedAt,
  'created_at': createdAt ?? publishedAt,
};

void main() {
  group('UpdateService.selectTargetRelease', () {
    test(
      'picks the later-published same-day nightly even when GitHub lists it '
      'below an older one (the reported bug)',
      () {
        // GitHub returned the OLDER build first; the newer manual build (later
        // published_at) is lower in the list. The tags differ only by SHA, so
        // nothing in the string can rank them.
        final releases = [
          _rel(
            tag: 'nightly-rawhide.20260718.b503c85',
            prerelease: true,
            publishedAt: '2026-07-18T09:32:53Z',
          ),
          _rel(
            tag: 'nightly-rawhide.20260718.aaaaaaa',
            prerelease: true,
            publishedAt: '2026-07-18T14:05:00Z', // manual rebuild, published later
          ),
        ];

        final chosen = UpdateService.selectTargetRelease(releases, true);
        expect(chosen?['tag_name'], 'nightly-rawhide.20260718.aaaaaaa');
      },
    );

    test('stable build never selects a pre-release', () {
      final releases = [
        _rel(
          tag: 'nightly-rawhide.20260718.aaaaaaa',
          prerelease: true,
          publishedAt: '2026-07-18T14:05:00Z',
        ),
        _rel(
          tag: 'v0.9.8',
          prerelease: false,
          publishedAt: '2026-07-10T00:00:00Z',
        ),
      ];
      final chosen = UpdateService.selectTargetRelease(releases, false);
      expect(chosen?['tag_name'], 'v0.9.8');
    });

    test('nightly build skips stable and unflagged betas, picks newest nightly', () {
      final releases = [
        _rel(
          tag: 'v0.9.8',
          prerelease: false,
          publishedAt: '2026-07-19T00:00:00Z', // newest overall, but wrong channel
        ),
        _rel(
          tag: 'nightly-rawhide.20260717.4360257',
          prerelease: true,
          publishedAt: '2026-07-17T06:07:24Z',
        ),
        _rel(
          tag: 'nightly-rawhide.20260718.b503c85',
          prerelease: true,
          publishedAt: '2026-07-18T09:32:53Z',
        ),
        // prerelease flag not set but tag carries "beta" — must still count as
        // pre-release for a nightly channel (both are "effectively beta").
        _rel(
          tag: '0.9.9-beta1',
          prerelease: false,
          publishedAt: '2026-07-16T00:00:00Z',
        ),
      ];
      final chosen = UpdateService.selectTargetRelease(releases, true);
      expect(chosen?['tag_name'], 'nightly-rawhide.20260718.b503c85');
    });

    test('falls back to created_at when published_at is null', () {
      final releases = [
        _rel(
          tag: 'nightly-rawhide.20260718.older',
          prerelease: true,
          publishedAt: '2026-07-18T01:00:00Z',
        ),
        _rel(
          tag: 'nightly-rawhide.20260718.newer',
          prerelease: true,
          publishedAt: null,
          createdAt: '2026-07-18T23:00:00Z',
        ),
      ];
      final chosen = UpdateService.selectTargetRelease(releases, true);
      expect(chosen?['tag_name'], 'nightly-rawhide.20260718.newer');
    });

    test('returns null when no release matches the channel', () {
      final releases = [
        _rel(
          tag: 'v0.9.8',
          prerelease: false,
          publishedAt: '2026-07-10T00:00:00Z',
        ),
      ];
      expect(UpdateService.selectTargetRelease(releases, true), isNull);
      expect(UpdateService.selectTargetRelease(const [], false), isNull);
    });
  });
}
