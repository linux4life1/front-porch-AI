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

// The documented identity gotcha, at the home grid's tap handler.
//
// ChatService.getSessionsForId resolves a 1:1 id by imagePath BASENAME
// (stableGroupId). Handing it `character.dbId` — the characters.id UUID — can
// never match, so it silently returns [], `sessions.length > 1` is false, and
// the "continue a chat / start a new one" picker is unreachable for every
// library character while the group tile's picker still works. This regressed
// once before (fixed in c72d0484, a duplicate copy of the line survived and
// was carried into home_page_chrome.dart by the god-file split).
//
// _handleTapCharacter is a private method on a `part of home_page.dart` State
// behind a Provider graph and a route push, so there is no unit seam to pump —
// this reads the call site directly, the same way chaos_global_toggle_test
// reads its three seed sites.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the home grid resolves sessions by stableGroupId, never the dbId', () {
    final src = File(
      'lib/ui/pages/home/home_page_chrome.dart',
    ).readAsStringSync();

    final handler = RegExp(
      r'Future<void> _handleTapCharacter\(.*?\n  \}',
      dotAll: true,
    ).firstMatch(src);
    expect(
      handler,
      isNotNull,
      reason: 'could not read _handleTapCharacter — if it moved, move this '
          'guard with it rather than deleting it',
    );
    final body = handler!.group(0)!;

    expect(
      body,
      contains('getSessionsForId'),
      reason: 'the tap handler no longer lists sessions at all',
    );
    expect(
      body.contains('character.dbId'),
      isFalse,
      reason: 'the tap handler passes the dbId UUID to getSessionsForId, which '
          'keys by image-filename basename — it returns [] for every '
          'character and the multi-chat picker never opens',
    );
    expect(
      body,
      contains('_getCharacterIdFromCard(character)'),
      reason: 'the tap handler must resolve the stable (basename) id',
    );
  });
}
