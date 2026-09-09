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

import 'package:front_porch_ai/services/waifu/waifu_jail.dart';

/// Permission gear for one Waifu Coder session. Not a personality.
enum WaifuMode { plan, build, yolo }

/// Sit-down Jail/Disk + honesty already on file for this porch.
class WaifuPorchConsent {
  const WaifuPorchConsent({
    required this.pathMode,
    required this.honestyAccepted,
  });

  final WaifuPathMode pathMode;
  final bool honestyAccepted;
}

/// New session in a known folder skips the honesty re-quiz when the
/// store already has pathMode + honesty for that porch.
bool waifuSkipHonestyQuiz(WaifuPorchConsent? consent) =>
    consent != null && consent.honestyAccepted;

/// Parse the parked-session map. A saved porch is sit-down consent;
/// [honestyAccepted] false is an explicit withhold.
WaifuPorchConsent? waifuPorchConsentFromMap(Map<dynamic, dynamic> map) {
  final folder = map['folderRoot']?.toString() ?? '';
  if (folder.isEmpty) return null;
  final pathModeName = map['pathMode']?.toString() ?? '';
  if (pathModeName.isEmpty && map['honestyAccepted'] != true) return null;
  final pathMode = pathModeName == 'wholeDisk'
      ? WaifuPathMode.wholeDisk
      : WaifuPathMode.folderJail;
  if (map['honestyAccepted'] == false) return null;
  final honesty = map['honestyAccepted'] == true || pathModeName.isNotEmpty;
  if (!honesty) return null;
  return WaifuPorchConsent(pathMode: pathMode, honestyAccepted: true);
}

/// Sit down Confirm is live only when every required piece is present.
/// Tools-unsupported is a hard block even with the honesty box ticked.
bool waifuCanSitDown({
  required bool honestyAccepted,
  required bool toolsSupported,
  required bool hasFolder,
  required bool hasCoworker,
}) {
  return honestyAccepted && toolsSupported && hasFolder && hasCoworker;
}

/// Send / loop gate. Either side false is a hard stop — no silent coding.
bool waifuCanUseTools({
  required bool sessionToolsSupported,
  required bool llmToolsSupported,
}) => sessionToolsSupported && llmToolsSupported;

/// Live ChatService / probe mapping. Untested stays open; known-no fails.
bool waifuResolveToolsSupported({
  required bool knownUnsupported,
  required bool paused,
}) => !knownUnsupported && !paused;
