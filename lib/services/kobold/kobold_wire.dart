// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The call to the engine that is open now, so Stop can cut it.

import 'dart:async';

import 'package:http/http.dart' as http;

/// The held call is cut in the zone that opened it. A cut that lands while
/// the socket is still connecting cancels the connect, and from another
/// error zone dart:io reports that cancellation as uncaught in the caller's
/// zone, though the caller awaited and caught it.
class KoboldWire {
  http.Client? _held;
  Zone _heldZone = Zone.root;

  /// [client] is the call on the wire now.
  void hold(http.Client client) {
    _held = client;
    _heldZone = Zone.current;
  }

  /// [client] has ended. It lets go of the wire only while it is still the
  /// call held: clearing a newer call's hold would leave its Stop with
  /// nothing to close.
  void release(http.Client? client) {
    if (identical(_held, client)) _held = null;
  }

  /// Whether [client] is still the call on the wire.
  bool holds(http.Client client) => identical(_held, client);

  /// Closes the call on the wire, if there is one.
  void cut() {
    final held = _held;
    _held = null;
    if (held != null) _heldZone.run(held.close);
  }
}
