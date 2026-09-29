// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/image/comfy_process_probe.dart';

/// What the OS would say about ports, users, file owners and process starts,
/// without asking it, so a test can describe another user's process or file,
/// or an OS that cannot answer (every answer can be null).
class FakeProbe implements ComfyProcessProbe {
  const FakeProbe({
    this.byPort = const {},
    this.me = 1000,
    this.owners = const {},
    this.permissions = const {},
    this.unknownOwners = const {},
    this.portsUnknown = false,
    this.permissionsUnknown = false,
    this.starts = const {},
    this.problems = const {},
    this.processOwners = const {},
    this.linkedAnywhere = false,
  });

  /// Which process id listens on which port.
  final Map<int, int> byPort;

  /// The user this app runs as. Null means the OS could not say.
  final int? me;

  /// The owner of a path, by its end. Anything else is owned by [me].
  final Map<String, int> owners;

  /// The permission bits of a path, by its end. Anything else is 0755.
  final Map<String, int> permissions;

  /// Paths, by their end, whose owner the OS cannot say.
  final Set<String> unknownOwners;

  /// True when there is no `lsof` or `ss`, so who listens cannot be said.
  final bool portsUnknown;

  /// True when permissions cannot be read.
  final bool permissionsUnknown;

  /// When each process started. A process not listed has no known start.
  final Map<int, DateTime> starts;

  /// A reason the OS layer would refuse a path (a NULL DACL, say), by its end.
  final Map<String, String> problems;

  /// The user that owns each process. One not listed has no known owner.
  final Map<int, int> processOwners;

  /// Every path is reported as a link, as a Windows junction would be.
  final bool linkedAnywhere;

  @override
  Future<Set<int>?> listeningPids(int port) async =>
      portsUnknown ? null : {if (byPort[port] != null) byPort[port]!};

  @override
  bool get tools => true;

  @override
  Future<int?> currentUid() async => me;

  @override
  Future<String?> currentPrincipal() async => me?.toString();

  @override
  Future<bool?> processIsMine(int pid) async {
    final owner = processOwners[pid];
    return owner == null || me == null ? null : owner == me;
  }

  @override
  Future<PathFacts?> pathFacts(String path, {required bool folder}) async {
    final owner = await fileOwner(path);
    final mode = await filePermissions(path);
    String? problem;
    for (final e in problems.entries) {
      if (path.endsWith(e.key)) problem = e.value;
    }
    return PathFacts(
      owner: owner?.toString(),
      ownerIsAdmin: owner == 0,
      isLink:
          linkedAnywhere || ComfyProcessProbe.linkedPath(path, folder: folder),
      othersCanWrite: mode == null ? null : mode & 0x12 != 0,
      problem: problem,
    );
  }

  @override
  Future<int?> fileOwner(String path) async {
    for (final unknown in unknownOwners) {
      if (path.endsWith(unknown)) return null;
    }
    for (final e in owners.entries) {
      if (path.endsWith(e.key)) return e.value;
    }
    return me;
  }

  @override
  Future<int?> filePermissions(String path) async {
    if (permissionsUnknown) return null;
    for (final e in permissions.entries) {
      if (path.endsWith(e.key)) return e.value;
    }
    return 493; // 0755
  }

  @override
  Future<DateTime?> processStart(int pid) async => starts[pid];
}
