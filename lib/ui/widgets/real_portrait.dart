// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';

/// Draws a character's picture only once it is known to be a real portrait.
///
/// A character made without a portrait still carries a flat coloured picture
/// (its card file needs one). That picture, a missing [file], and a picture
/// the [PlaceholderPortraitProbe] has not answered for yet all draw
/// [noPortrait], so the flat colour never flashes up first. Answers are
/// cached per file and [CharacterRepository.coverEpoch], which is bumped when
/// a portrait is replaced in place; with no repository above, the epoch is 0.
class RealPortrait extends StatelessWidget {
  const RealPortrait({
    super.key,
    required this.file,
    required this.portrait,
    required this.noPortrait,
  });

  final File? file;
  final Widget Function(BuildContext context, File file) portrait;
  final WidgetBuilder noPortrait;

  @override
  Widget build(BuildContext context) {
    final f = file;
    if (f == null) return noPortrait(context);
    final epoch = context.select<CharacterRepository?, int>(
      (repo) => repo?.coverEpoch ?? 0,
    );
    return FutureBuilder<bool>(
      // A FutureBuilder handed a new future keeps the old answer until the
      // new one lands; keyed per picture, a new file starts from its own.
      key: ValueKey('${f.path}|$epoch'),
      future: PlaceholderPortraitProbe.check(f, version: epoch),
      initialData: PlaceholderPortraitProbe.known(f, version: epoch),
      builder: (context, placeholder) => placeholder.data == false
          ? portrait(context, f)
          : noPortrait(context),
    );
  }
}
