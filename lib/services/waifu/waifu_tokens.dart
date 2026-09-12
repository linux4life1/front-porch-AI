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

/// Chrome meter helpers. Not an in-process Dart compact loop.
const kWaifuCompactAt = 0.75;
const kWaifuDefaultContextTokens = 8192;
const kWaifuCompactPrefix = '[Session compact]';
const kWaifuReadClipChars = 100000;

/// Fallback only — the bar prefers server usage when the backend sent it.
int waifuEstimateTokens(String text) {
  if (text.isEmpty) return 0;
  return (text.length / 4).ceil();
}

bool waifuShouldCompact({required int used, required int budget}) {
  final cap = budget < 1 ? kWaifuDefaultContextTokens : budget;
  if (cap <= 0) return false;
  return used >= (cap * kWaifuCompactAt).ceil();
}

/// Same number the sidebar bar shows: API usage when we have it.
int waifuFillUsed({
  required int tokensUsed,
  required bool fromApi,
  required int estimated,
}) => fromApi && tokensUsed > 0 ? tokensUsed : estimated;
