// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

/// A group member as this editor needs it: the RUNTIME id the realism engine
/// reads (`mid`), a display name, the optional legacy `originStableId` (used to
/// recover seeds from groups created before the id-keying fix), and an optional
/// avatar path for the header.
class GroupRealismMember {
  final String mid;
  final String name;
  final String? originStableId;
  final String? avatarPath;

  const GroupRealismMember({
    required this.mid,
    required this.name,
    this.originStableId,
    this.avatarPath,
  });
}
