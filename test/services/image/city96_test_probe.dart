// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/image/comfy_process_probe.dart';

/// What the OS would say about ports, users and file owners, without asking
/// it, so a test can describe another user's process or file.
class FakeProbe implements ComfyProcessProbe {
  const FakeProbe({this.byPort = const {}, this.me, this.owners = const {}});

  /// Which process id listens on which port.
  final Map<int, int> byPort;

  /// The user this app runs as. Null means the OS could not say.
  final int? me;

  /// The owner of a path, by its end. Anything else is owned by [me].
  final Map<String, int> owners;

  @override
  Future<Set<int>?> listeningPids(int port) async => {
    if (byPort[port] != null) byPort[port]!,
  };

  @override
  Future<int?> currentUid() async => me;

  @override
  Future<int?> fileOwner(String path) async {
    for (final e in owners.entries) {
      if (path.endsWith(e.key)) return e.value;
    }
    return me;
  }
}
