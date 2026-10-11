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

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/database/database.dart';
// Siblings of this file's own barrel (services.dart lives in this directory),
// so these are direct imports by the barrel policy's structural exemption.
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/services/world_repository.dart';

/// The database to use for a one-off query from the widget tree.
///
/// `Provider<AppDatabase>.value(value: db)` in `main.dart` is a snapshot taken
/// at startup and can never be updated — the provider tree is built inside
/// `runApp`, not inside a State. After a stable-DB import, a storage-root move
/// or a backup restore, [reopenAndRebindDatabase] replaces the singleton, and
/// every widget still reading the provider gets the *closed* database instead.
/// That is exactly how the Database Cleanup dialog, the Data Bank, the
/// character export/transfer sheet and the Stoop upload pages kept throwing
/// "database was closed" until the app was restarted.
///
/// Prefers the live singleton and falls back to the provider, so tests that
/// pump a widget over a provided database (without ever calling
/// `AppDatabase.instance()`) keep working unchanged.
AppDatabase liveDatabase(BuildContext context) =>
    AppDatabase.current ?? Provider.of<AppDatabase>(context, listen: false);

/// Reopens the database and re-points every service that caches a handle at
/// the new instance, then reloads the data those services keep in memory.
///
/// Three flows swap the database file underneath a running app: importing a
/// stable DB into a beta build, moving the storage root, and restoring a
/// backup. All three close the live database, which leaves every service
/// holding a handle whose next query throws. Two hand-maintained copies of
/// this rebind already existed (`main.dart` and the storage-path picker) and
/// had already drifted apart — neither ever rebound the RAG [MemoryService] —
/// while the Backups page had no rebind at all and simply told the user to
/// restart. One implementation means a service added here is fixed for every
/// flow at once.
///
/// [cleanOrphanedImages] deletes portrait PNGs that no character references any
/// more. That is safe after an *import*, where the incoming database is the new
/// source of truth. It is **never** safe after a *restore*: an older snapshot
/// legitimately lacks every character created since it was taken, so their
/// portraits would be deleted permanently — the backup can bring the rows back,
/// nothing can bring the art back.
///
/// Returns the reopened database, or null when the rebind could not complete.
/// Callers must treat null as "the app really does need a restart" rather than
/// as success, because the services are then still on the closed handle.
Future<AppDatabase?> reopenAndRebindDatabase(
  BuildContext context, {
  bool cleanOrphanedImages = false,
}) async {
  try {
    // Idempotent, and load-bearing. `close()` alone does NOT clear the static
    // singleton, so a caller that closed its own handle and then called
    // `AppDatabase.instance()` was handed back the very object it had just
    // closed. The flows that must close before touching the file (storage move,
    // restore) already reset it and this is a no-op for them.
    await AppDatabase.closeAndReset();
    final newDb = await AppDatabase.instance();
    if (!context.mounted) return null;

    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    final personaService = Provider.of<UserPersonaService>(
      context,
      listen: false,
    );
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final worldRepo = Provider.of<WorldRepository>(context, listen: false);

    charRepo.updateDatabase(newDb);
    folderService.updateDatabase(newDb);
    personaService.updateDatabase(newDb);
    groupRepo.updateDatabase(newDb);
    worldRepo.updateDatabase(newDb);
    // ChatService.updateDatabase also re-points the MemoryService it owns, so
    // RAG memory survives the swap instead of querying the closed handle.
    final chatService = Provider.of<ChatService>(context, listen: false);
    final storyRepo = Provider.of<StoryRepository>(context, listen: false);
    chatService.updateDatabase(newDb);
    storyRepo.updateDatabase(newDb);
    // The pipeline binds its own handle at construction; without this it kept
    // the CLOSED one until an unrelated rebuild (Porch Stories looked empty).
    Provider.of<StoryPipelineService>(
      context,
      listen: false,
    ).updateDatabase(newDb);
    Provider.of<WebServerHost>(context, listen: false).setDatabase(newDb);

    // Every in-memory cache is now a view of the previous database file.
    await charRepo.loadCharacters();
    if (cleanOrphanedImages) {
      await charRepo.cleanOrphanedPngs();
    }
    await folderService.reload();
    await personaService.reload();
    await groupRepo.reload();
    await worldRepo.loadWorlds();
    await storyRepo.loadProjects();
    // The open chat's transcript is ALSO a view of the previous file. Without
    // this reload, the next _saveChat upserts the pre-swap messages back into
    // the swapped database — a user who restored a 10-message snapshot while
    // a 20-message chat was open silently un-restored that conversation the
    // moment they sent one more line (1.3 sweep, 2026-08-15). Import, move
    // and restore all reload here.
    await chatService.reloadCurrentSession();
    return newDb;
  } catch (e) {
    debugPrint('[DB] Rebind after database swap failed: $e');
    return null;
  }
}
