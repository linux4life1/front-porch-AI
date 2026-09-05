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

/// Permission gear for one Desk session. Not a personality.
enum DeskMode { plan, build, yolo }

/// Sit down Confirm is live only when every required piece is present.
/// Tools-unsupported is a hard block even with the honesty box ticked.
bool deskCanSitDown({
  required bool honestyAccepted,
  required bool toolsSupported,
  required bool hasFolder,
  required bool hasCoworker,
}) {
  return honestyAccepted && toolsSupported && hasFolder && hasCoworker;
}
