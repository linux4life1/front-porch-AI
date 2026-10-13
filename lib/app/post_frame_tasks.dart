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
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:provider/provider.dart';

/// Post-first-frame chores MyApp starts once its home has built. Each takes
/// a [BuildContext] below the provider graph.

Future<void> checkForAppUpdates(BuildContext context) async {
  final updateService = Provider.of<UpdateService>(context, listen: false);
  await updateService.initialize();

  // Only check for updates on platforms that support self-update
  if (!UpdateService.isSupported) return;
  if (!updateService.autoCheckEnabled) return;

  final hasUpdate = await updateService.checkForUpdate();
  if (hasUpdate && context.mounted) {
    // Awaited so the engine's box below never lands on top of this one.
    await UpdateDialog.show(context);
  }
}

/// After the app's own update check: an engine below the floor, or a
/// newer release not put off, gets its box. Nothing when KoboldCpp is not
/// installed; it is optional.
Future<void> checkKoboldEngine(BuildContext context) async {
  final manager = Provider.of<BackendManager>(context, listen: false);
  final gate = await manager.updateGate();
  if (gate == KoboldUpdateGate.nothing || !context.mounted) return;
  await KoboldUpdateDialog.show(context, manager, gate);
}

Future<void> autoStartWebServer(BuildContext context) async {
  final storage = Provider.of<StorageService>(context, listen: false);
  await storage.initialized;
  if (!storage.webServerSettings.webServerEnabled) return;

  final webServer = Provider.of<WebServerHost>(context, listen: false);
  // Crash-loop-safe: a hung or crashing start disables the server instead of
  // re-crashing on every launch and locking the user out (see startSafely).
  await webServer.startSafely(
    storage.webServerSettings.webServerPort,
    isAutoStart: true,
  );
}
