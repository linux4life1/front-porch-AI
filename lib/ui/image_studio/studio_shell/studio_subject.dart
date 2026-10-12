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

import 'package:front_porch_ai/services/services.dart';

typedef StudioGroupMember = ({String name, String description, String? dbId});

/// The Studio's active subject: Freeform / Character / Persona, plus a picked
/// group member or the whole-cast group shot, and the library targets those
/// resolve to. `ImageStudio.mode` is only the initial selection.
class StudioSubject {
  StudioSubject(this.mode);

  ImageGenMode mode;

  // Group-chat subject: the picked cast member, or a whole-cast "group shot".
  // Both null/false → fall back to the 1:1 character passed on the widget.
  String? _pickedName;
  String? _pickedDbId;
  bool _groupShot = false;

  bool get groupShot => _groupShot;

  /// Switch subject. Leaving the Character subject clears any group pick/shot.
  void select(ImageGenMode next) {
    mode = next;
    if (next != ImageGenMode.characterPortrait) {
      _pickedName = null;
      _pickedDbId = null;
      _groupShot = false;
    }
  }

  /// Portrait one chosen cast [member] (reliable — a single subject), or with
  /// null the caveated whole-cast "group shot".
  void pickGroup(StudioGroupMember? member) {
    _pickedName = member?.name;
    _pickedDbId = member?.dbId;
    _groupShot = member == null;
    mode = ImageGenMode.characterPortrait;
  }

  /// Name for the portrait context: a whole-cast label, a picked group member,
  /// else the 1:1 chat character.
  String? charName(List<StudioGroupMember> cast, String? characterName) {
    if (_groupShot) {
      return 'the group (${cast.map((c) => c.name).join(', ')})';
    }
    return _pickedName ?? characterName;
  }

  /// The library id an Expression pack imports into: the picked member's, else
  /// the 1:1 character's. Null (group shot/persona/freeform) hides the button.
  String? packTargetDbId(String? characterDbId) {
    if (_groupShot) return null;
    if (mode != ImageGenMode.characterPortrait) return null;
    return _pickedName != null ? _pickedDbId : characterDbId;
  }

  bool get isPortrait =>
      mode == ImageGenMode.characterPortrait || mode == ImageGenMode.userAvatar;

  /// The library (dbId, name) a saved LOOK targets: the picked group member's
  /// origin, else the 1:1 character. Unlike [packTargetDbId] it does NOT gate
  /// on portrait mode — any generated image (a scene, an outfit) can be a look.
  /// Null for a group shot / persona / no character → the button hides.
  (String, String)? lookTarget(String? characterDbId, String? characterName) {
    if (_groupShot) return null;
    final dbId = _pickedName != null ? _pickedDbId : characterDbId;
    final name = _pickedName ?? characterName;
    if (dbId == null || name == null) return null;
    return (dbId, name);
  }
}
