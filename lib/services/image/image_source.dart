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

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Where a generated picture came from, as Image Studio's Recent shelf sorts
/// and labels it. The [key] is what the shelf's notes file and the phone
/// carry; [label] is what a person reads.
enum ImageSourceKind {
  studio('studio', 'Studio'),
  edit('edit', 'Edits'),
  creator('creator', 'Character creator'),
  chat('chat', 'Chat'),
  guest('guest', 'Guests'),
  story('story', 'Story Studio');

  const ImageSourceKind(this.key, this.label);

  final String key;

  /// The chip's words.
  final String label;

  /// The kind stored as [key], or null for a key this build has no word for.
  static ImageSourceKind? fromKey(String? key) {
    for (final kind in values) {
      if (kind.key == key) return kind;
    }
    return null;
  }
}

/// A picture's source and the name that goes with it (the character being
/// created, the chat, the guest, the story). [subject] may be empty.
@immutable
class ImageSource {
  const ImageSource(this.kind, [this.subject = '']);

  final ImageSourceKind kind;
  final String subject;

  /// The line on the picture on show: "Character creator · Ada".
  String get line => switch (kind) {
    ImageSourceKind.studio => 'Image Studio · Create',
    ImageSourceKind.edit => 'Image Studio · Edit',
    ImageSourceKind.creator => _with('Character creator'),
    ImageSourceKind.chat => subject.isEmpty ? 'Chat' : 'Chat with $subject',
    ImageSourceKind.guest => _with('Guest portrait'),
    ImageSourceKind.story => _with('Story Studio'),
  };

  String _with(String what) => subject.isEmpty ? what : '$what · $subject';
}

const Symbol _zoneKey = #fpai_image_source;

/// Run [body] with every picture it generates marked as coming from
/// [source]. The generator reads the mark when it keeps a picture on the
/// Recent shelf, so a screen tags its pictures without the generator's
/// signature changing.
Future<T> withImageSource<T>(ImageSource source, Future<T> Function() body) =>
    runZoned(body, zoneValues: {_zoneKey: source});

/// The source the running code was given by [withImageSource], or null for
/// a picture made in the Studio itself.
ImageSource? get currentImageSource => Zone.current[_zoneKey] as ImageSource?;
