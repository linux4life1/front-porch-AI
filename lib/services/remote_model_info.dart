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

/// Metadata for a remote model, including pricing.
/// (Extracted from open_router_service.dart, which re-exports it — existing
/// importers are untouched.)
class RemoteModelInfo {
  final String id;
  final String name;
  final double? promptCostPerMillion; // USD per 1M input tokens
  final double? completionCostPerMillion; // USD per 1M output tokens

  const RemoteModelInfo({
    required this.id,
    this.name = '',
    this.promptCostPerMillion,
    this.completionCostPerMillion,
  });

  /// Human-readable pricing string, e.g. "$0.50 / $1.50"
  String get pricingLabel {
    if (promptCostPerMillion == null && completionCostPerMillion == null) {
      return 'Pricing unavailable';
    }
    final input = promptCostPerMillion != null
        ? '\$${promptCostPerMillion!.toStringAsFixed(2)}'
        : '?';
    final output = completionCostPerMillion != null
        ? '\$${completionCostPerMillion!.toStringAsFixed(2)}'
        : '?';
    return '$input in / $output out per 1M tokens';
  }

  bool get isFree =>
      (promptCostPerMillion == null || promptCostPerMillion == 0) &&
      (completionCostPerMillion == null || completionCostPerMillion == 0);
}
