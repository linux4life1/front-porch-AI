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

/// Single source of truth for the app version.
/// Update this constant whenever a new release is made.
/// This avoids reliance on platform-specific version resource extraction
/// (e.g., PackageInfo.fromPlatform) which can be unreliable on Windows.
const String appVersion = '0.9.8.0.1';

/// Whether the current build is a pre-release (alpha, beta, rc, dev).
/// Pre-release builds use a separate database file to protect the stable
/// database from schema changes that may be incompatible with older versions.
bool get isPreRelease {
  final lower = appVersion.toLowerCase();
  return lower.contains('-alpha') ||
      lower.contains('-beta') ||
      lower.contains('-rc') ||
      lower.contains('-dev');
}

/// The stable version number without the pre-release suffix.
/// e.g. '0.9.0-alpha1' → '0.9.0'
String get stableVersionBase => appVersion.split('-').first;
