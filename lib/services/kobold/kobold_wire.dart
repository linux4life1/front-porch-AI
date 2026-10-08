// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The call to the engine that is open now, so Stop can cut it.

import 'package:http/http.dart' as http;

class KoboldWire {
  http.Client? _held;

  /// [client] is the call on the wire now.
  void hold(http.Client client) => _held = client;

  /// [client] has ended. It lets go of the wire only while it is still the
  /// call held: clearing a newer call's hold would leave its Stop with
  /// nothing to close.
  void release(http.Client? client) {
    if (identical(_held, client)) _held = null;
  }

  /// Closes the call on the wire, if there is one.
  void cut() {
    _held?.close();
    _held = null;
  }
}
