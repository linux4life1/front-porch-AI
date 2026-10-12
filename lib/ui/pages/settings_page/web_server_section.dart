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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/web_server_host.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// A web-server port typed into the Advanced tab, or null when the text is
/// not a usable port. Null means "leave the saved port alone" — the field
/// commits on focus loss as well as Enter, so half-typed or cleared text
/// must never silently overwrite a working port.
int? parseWebServerPort(String raw) {
  final port = int.tryParse(raw.trim());
  if (port == null || port < 1 || port > 65535) return null;
  return port;
}

/// Latest text typed into the Web Server port field. It commits on focus
/// loss too, and has to outlive the rebuilds that storage/web-server
/// notifications trigger while the field is being edited, so the page owns
/// one and hands it to [WebServerSection].
class WebServerPortDraft {
  String? pending;
}

/// One shared start-attempt flow for the toggle and the failure dialog's
/// retry button. Failures show a warm, plain-English dialog (maintainer
/// directive 2026-08-04: most users are non-technical and a vanishing
/// toast left them stuck) with a one-tap "use a free port" fix whenever
/// the port is the problem — no networking knowledge needed.
Future<void> attemptWebServerStart(
  BuildContext context,
  StorageService storage,
  WebServerHost webServer,
) async {
  // startSafely reverts + disables on failure so a bad start can never
  // leave the app in a launch crash loop.
  final ok = await webServer.startSafely(
    storage.webServerSettings.webServerPort,
  );
  if (!context.mounted) return;
  if (ok) {
    // Guide the user through how they'll reach it.
    await WebAccessSetupDialog.show(context);
    return;
  }
  final altPort = webServer.lastStartPortConflict
      ? await webServer.findFreePortNear(
          storage.webServerSettings.webServerPort,
        )
      : null;
  if (!context.mounted) return;

  Future<void> retry() async {
    Navigator.of(context).pop();
    if (altPort != null) {
      await storage.webServerSettings.setWebServerPort(altPort);
    }
    await storage.webServerSettings.setWebServerEnabled(true);
    if (!context.mounted) return;
    await attemptWebServerStart(context, storage, webServer);
  }

  await showWarmDialog<void>(
    context,
    title: 'Web server couldn’t start',
    icon: Icons.wifi_tethering_off,
    width: 380,
    content: Text(
      webServer.lastStartError ??
          'Something unexpected stopped it. Try again in a moment.',
      style: TextStyle(
        color: AppColors.textSecondary(context),
        fontSize: 13,
        height: 1.4,
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Close'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.porchAmberOf(context),
          foregroundColor: AppColors.onChaosAccent,
        ),
        onPressed: () => retry(),
        child: Text(
          altPort != null ? 'Use port $altPort instead' : 'Try again',
        ),
      ),
    ],
  );
}

/// The ONE commit path for the web-server port field — Enter and focus
/// loss both land here, so clicking away can no longer discard a typed
/// port. Unparseable or out-of-range text leaves the saved port alone
/// (see [parseWebServerPort]); an unchanged port is a no-op so a blur
/// never restarts a running server for nothing.
Future<void> commitWebServerPort(
  String value,
  StorageService storage,
  WebServerHost webServer,
  WebServerPortDraft draft,
) async {
  draft.pending = null;
  final port = parseWebServerPort(value);
  if (port == null || port == storage.webServerSettings.webServerPort) return;
  await storage.webServerSettings.setWebServerPort(port);
  if (webServer.isRunning) {
    await webServer.stop();
    await webServer.start(port);
  }
}

/// The Advanced tab's Web Server card: enable switch, port, login, status,
/// LAN address and connected client.
class WebServerSection extends StatelessWidget {
  const WebServerSection({super.key, required this.portDraft});

  final WebServerPortDraft portDraft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer2<StorageService, WebServerHost>(
      builder: (context, storage, webServer, _) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        webServer.isRunning
                            ? Icons.wifi_tethering
                            : Icons.wifi_tethering_off,
                        color: webServer.isRunning
                            ? AppColors.bondHighOf(context)
                            : AppColors.textTertiary(context),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Enable Web Server',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Switch(
                    value: storage.webServerSettings.webServerEnabled,
                    activeTrackColor: AppColors.porchAmberOf(context),
                    onChanged: (val) async {
                      await storage.webServerSettings.setWebServerEnabled(val);
                      if (val) {
                        await attemptWebServerStart(
                          context,
                          storage,
                          webServer,
                        );
                      } else {
                        await webServer.stop();
                      }
                    },
                  ),
                ],
              ),
              if (storage.webServerSettings.webServerEnabled) ...[
                Divider(color: AppColors.borderOf(context)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Port', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 120,
                            // Enter was the ONLY commit path: a typed port was
                            // silently dropped when the user clicked away. The
                            // pending text lives on [portDraft] because storage
                            // and webServer notifications rebuild this field
                            // mid-edit.
                            child: Focus(
                              // Blur listener only — a focusable wrapper would
                              // add a Tab stop in front of the field that shows
                              // no caret and swallows typing.
                              canRequestFocus: false,
                              onFocusChange: (hasFocus) {
                                if (hasFocus) return;
                                final pending = portDraft.pending;
                                if (pending == null) return;
                                commitWebServerPort(
                                  pending,
                                  storage,
                                  webServer,
                                  portDraft,
                                );
                              },
                              child: TextFormField(
                                // Keyed on the port so the one-tap "Use port N"
                                // fix in the failure dialog refreshes the field.
                                key: ValueKey(
                                  storage.webServerSettings.webServerPort,
                                ),
                                initialValue: storage
                                    .webServerSettings
                                    .webServerPort
                                    .toString(),
                                keyboardType: TextInputType.number,
                                style: TextStyle(
                                  color: AppColors.textPrimary(context),
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: theme.scaffoldBackgroundColor,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                                onChanged: (val) => portDraft.pending = val,
                                onFieldSubmitted: (val) => commitWebServerPort(
                                  val,
                                  storage,
                                  webServer,
                                  portDraft,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Login', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                if (webServer.auth case final auth?)
                  WebLoginSection(
                    // Rebuild after a reset from the web side too.
                    key: ValueKey(webServer.isRunning),
                    auth: auth,
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Status', style: theme.textTheme.bodySmall),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: webServer.isRunning
                                      ? AppColors.bondHighOf(context)
                                      : AppColors.negativeAccentOf(context),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                webServer.isRunning ? 'Running' : 'Stopped',
                                style: TextStyle(
                                  color: webServer.isRunning
                                      ? AppColors.bondHighOf(context)
                                      : AppColors.negativeAccentOf(context),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (webServer.lanIp != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.porchAmberOf(
                        context,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.porchAmberOf(
                          context,
                        ).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.language,
                          color: AppColors.porchAmberOf(context),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SelectableText(
                            'http://${webServer.lanIp}:${storage.webServerSettings.webServerPort}',
                            style: TextStyle(
                              color: AppColors.porchAmberOf(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (webServer.hasActiveClient) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.porchHoneyOf(
                        context,
                      ).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.porchHoneyOf(
                          context,
                        ).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.devices,
                          color: AppColors.porchHoneyOf(context),
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Client connected: ${webServer.connectedClientIp ?? "Unknown"}',
                            style: TextStyle(
                              color: AppColors.porchHoneyOf(context),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }
}
