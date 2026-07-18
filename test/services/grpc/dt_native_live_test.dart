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

// Live TLS handshake + Echo against a REAL Draw Things server. Exists
// because the native client shipped with chain verification that could
// never pass (the pinned PEM is DT's leaf cert; dart:io has no
// partial-chain trust, unlike Python gRPC), and the silent sidecar
// fallback hid it until the signed nightly — where the sidecar also
// crashes. Gated: set FP_DT_LIVE=1 with Draw Things' gRPC server
// listening on 127.0.0.1:7859 (override via FP_DT_LIVE_PORT).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/grpc/dt_native/draw_things_native_client.dart';

void main() {
  final live = Platform.environment['FP_DT_LIVE'] == '1';
  final port =
      int.tryParse(Platform.environment['FP_DT_LIVE_PORT'] ?? '') ?? 7859;

  test(
    'native TLS pinning completes a handshake + Echo with real Draw Things',
    () async {
      final client = DrawThingsNativeClient(host: '127.0.0.1', port: port);
      try {
        final reply = await client.echo();
        // Any reply proves the TLS handshake + gRPC round-trip succeeded;
        // DT answers Echo with a banner/version string.
        expect(reply, isNotNull);
      } finally {
        await client.shutdown();
      }
    },
    skip: live ? false : 'FP_DT_LIVE not set — needs a running Draw Things',
  );
}
