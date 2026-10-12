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

/// Stance for condition skins (phase 2 fully authors these; built-ins carry
/// ordinary/harsh so dressCue can stay one code path).
enum WeatherStance { pleasant, ordinary, harsh, dangerous, deadly }

WeatherStance weatherStanceFromName(String? name) {
  switch (name?.toLowerCase()) {
    case 'pleasant':
      return WeatherStance.pleasant;
    case 'harsh':
      return WeatherStance.harsh;
    case 'dangerous':
      return WeatherStance.dangerous;
    case 'deadly':
      return WeatherStance.deadly;
    default:
      return WeatherStance.ordinary;
  }
}

class ConditionSkin {
  final String label;
  final String? emoji;
  final WeatherStance stance;
  final String? flavour;

  const ConditionSkin({
    required this.label,
    this.emoji,
    this.stance = WeatherStance.ordinary,
    this.flavour,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    if (emoji != null) 'emoji': emoji,
    'stance': stance.name,
    if (flavour != null && flavour!.isNotEmpty) 'flavour': flavour,
  };

  factory ConditionSkin.fromJson(Map<String, dynamic> json) => ConditionSkin(
    label: json['label']?.toString() ?? '',
    emoji: json['emoji']?.toString(),
    stance: weatherStanceFromName(json['stance']?.toString()),
    flavour: json['flavour']?.toString() ?? json['flavor']?.toString(),
  );
}
