// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group, group-member, folder, and persona queries.

part of 'database.dart';

/// Group, group-member, folder, and persona queries.
extension AppDatabaseGroupQueries on AppDatabase {
  // ── Group Queries ───────────────────────────────────────────────────

  Future<List<Group>> getAllGroups() =>
      (select(groups)..where((g) => g.deletedAt.isNull())).get();

  Future<Group?> getGroupById(String id) =>
      (select(groups)..where((g) => g.id.equals(id))).getSingleOrNull();

  Future<int> insertGroup(GroupsCompanion group) async {
    final result = await into(groups).insert(group);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updateGroup(GroupsCompanion group) async {
    // IMPORTANT: Use .write() not .replace() — .replace() overwrites the entire
    // row, so any column absent from the companion (e.g. folder_id, which is
    // owned by FolderService rather than the repository's save path) would be
    // silently reset to null/default on every group save.
    final rows = await (update(
      groups,
    )..where((g) => g.id.equals(group.id.value))).write(group);
    await bumpSyncVersion();
    return rows > 0;
  }

  /// Update ONLY the folder membership for a group (preserves all other data).
  /// The group analogue of [updateCharacter]'s folderId writes; null = top level.
  Future<void> updateGroupFolderId(String id, String? folderId) async {
    await (update(groups)..where((g) => g.id.equals(id))).write(
      GroupsCompanion(
        folderId: Value(folderId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    await bumpSyncVersion();
  }

  /// Journal, growth, embeddings, objectives, worlds — same cascade as a
  /// single-chat delete. A raw messages+sessions wipe left those rows
  /// behind (audit P1: leftover embeddings still held the transcript).
  Future<void> _cascadeGroupSessions(String groupId) async {
    final groupSessions = await (select(
      sessions,
    )..where((s) => s.groupId.equals(groupId))).get();
    for (final s in groupSessions) {
      await deleteSessionById(s.id);
    }
  }

  Future<int> deleteGroupById(String id) async {
    await _cascadeGroupSessions(id);

    // Clean group-owned members (decoupled storage). Their private avatar files under
    // groups/<id>/ are cleaned by the repository layer using StorageService.
    await customStatement('DELETE FROM group_members WHERE group_id = ?', [id]);

    final count = await (delete(groups)..where((g) => g.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  /// Soft-delete a group (sets deletedAt + updatedAt) while hard-cascading its
  /// dependent sessions and messages. The soft-deleted row stays so cloud DB
  /// sync can propagate the deletion flag and the merge layer can prevent
  /// resurrection on other devices.
  Future<int> softDeleteGroupById(String id) async {
    await _cascadeGroupSessions(id);

    // Clean group-owned members (decoupled storage). Avatar files cleaned by repo layer.
    await customStatement('DELETE FROM group_members WHERE group_id = ?', [id]);

    final now = DateTime.now();
    final count = await (update(groups)..where((g) => g.id.equals(id))).write(
      GroupsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
    await bumpSyncVersion();
    return count;
  }

  // ── Group Member Queries (decoupled characters, UUID keys, no blobs) ──
  // See GroupMembers table docs for contract. All per-member state keys use the UUID id.

  Future<List<GroupMemberRow>> getGroupMembers(String groupId) =>
      (select(groupMembers)..where((m) => m.groupId.equals(groupId))).get();

  Future<int> insertGroupMember(GroupMembersCompanion member) async {
    final result = await into(groupMembers).insert(member);
    await bumpSyncVersion();
    return result;
  }

  Future<void> updateGroupMember(GroupMembersCompanion member) async {
    await (update(
      groupMembers,
    )..where((m) => m.id.equals(member.id.value))).write(member);
    await bumpSyncVersion();
  }

  /// Delete a single group member row by its instance id (the UUID primary key).
  /// Used when one character is removed from a group (not full-group teardown).
  Future<int> deleteGroupMember(String memberId) async {
    final count = await (delete(
      groupMembers,
    )..where((m) => m.id.equals(memberId))).go();
    await bumpSyncVersion();
    return count;
  }

  // ── Folder Queries ──────────────────────────────────────────────────

  Future<List<Folder>> getAllFolders() =>
      (select(folders)..where((f) => f.deletedAt.isNull())).get();

  Future<String> insertFolder(FoldersCompanion folder) async {
    final id = folder.id.present ? folder.id.value : _uuid.v4();
    folder = folder.copyWith(id: Value(id));
    await into(folders).insert(folder);
    await bumpSyncVersion();
    return id;
  }

  Future<int> deleteFolderById(String id) async {
    final count = await (delete(folders)..where((f) => f.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> updateFolder(FoldersCompanion folder) async {
    await (update(
      folders,
    )..where((f) => f.id.equals(folder.id.value))).write(folder);
    await bumpSyncVersion();
  }

  // ── Persona Queries ─────────────────────────────────────────────────

  Future<List<Persona>> getAllPersonas() =>
      (select(personas)..where((p) => p.deletedAt.isNull())).get();

  Future<int> insertPersona(PersonasCompanion persona) async {
    final result = await into(personas).insert(persona);
    await bumpSyncVersion();
    return result;
  }

  Future<bool> updatePersona(PersonasCompanion persona) async {
    final result = await update(personas).replace(persona);
    await bumpSyncVersion();
    return result;
  }

  Future<int> deletePersonaById(String id) async {
    final count = await (delete(personas)..where((p) => p.id.equals(id))).go();
    await bumpSyncVersion();
    return count;
  }

  Future<void> setActivePersona(String id) async {
    await transaction(() async {
      // Deactivate all
      await (update(
        personas,
      )).write(const PersonasCompanion(isActive: Value(false)));
      // Activate the chosen one
      await (update(personas)..where((p) => p.id.equals(id))).write(
        const PersonasCompanion(isActive: Value(true)),
      );
    });
    await bumpSyncVersion();
  }
}
