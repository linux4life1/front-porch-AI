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

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/group_member_start_overlay.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';

/// What a new chat of [group] starts its [cast] from, keyed by member id
/// ([idOf]): the group's stored seeds with each member's own copy laid over
/// them ([memberStartSeeds]). Realism for the new chat follows whether any
/// member starts with a seed.
Map<String, Map<String, dynamic>> groupStartSeeds(
  GroupChat group,
  Iterable<CharacterCard> cast,
  String Function(CharacterCard) idOf,
) => memberStartSeeds(parseGroupRealismSeeds(group.defaultMemberRealismState), [
  for (final c in cast) (mid: idOf(c), ext: c.frontPorchExtensions),
], definitionJson: group.defaultMemberRealismState);

/// [groupStartSeeds] as the chat's per-member realism state.
Map<String, GroupMemberRealism> groupStartMembers(
  GroupChat group,
  Iterable<CharacterCard> cast,
  String Function(CharacterCard) idOf,
) => groupStartSeeds(
  group,
  cast,
  idOf,
).map((k, v) => MapEntry(k, GroupMemberRealism.fromJson(v)));
