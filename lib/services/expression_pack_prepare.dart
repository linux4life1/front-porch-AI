// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'expression_pack_base_check.dart';
import 'expression_pack_convert.dart';
import 'expression_pack_service.dart';

/// What a pack is built from: the base at its generation size, and whether it
/// was made from a JPEG or WebP that had to be converted to a PNG first.
typedef PackBase = ({Uint8List bytes, int width, int height, bool converted});

/// The words shown beside a pack made from a converted picture.
const String kPackConvertedNote =
    'Converted your portrait to PNG for the pack.';

const _formats = PackBaseRefusal(
  'Please use a PNG, JPEG or still WebP picture.',
);

/// Makes [raw], a portrait or a picture the person chose, into the pack's
/// base. A PNG goes straight to [normalizePackBase]. A JPEG or a still WebP is
/// first converted to a PNG in an isolate that is stopped if it takes too long
/// ([convertPackBase]), and that PNG goes through the same checks and the same
/// normalising: a pack base is always a PNG that has been inspected. Anything
/// else (a GIF, a BMP, an animated WebP, bytes that are nothing) is refused.
/// The original is never touched, and the converted PNG is kept nowhere: it is
/// the base, in memory, and the expressions made from it are all that is saved.
///
/// Null when there is no base; [onRefused] then gets the reason when there is
/// one to show.
Future<PackBase?> preparePackBase(
  Uint8List raw, {
  void Function(PackBaseRefusal refusal)? onRefused,
}) async {
  var png = raw;
  var converted = false;
  switch (packPictureKind(raw)) {
    case PackPictureKind.png:
      break;
    case PackPictureKind.jpeg || PackPictureKind.webp:
      final made = await convertPackBase(raw);
      final refusal = made.refusal;
      if (refusal != null) {
        onRefused?.call(refusal);
        return null;
      }
      png = made.png!;
      converted = true;
    case PackPictureKind.other:
      onRefused?.call(_formats);
      return null;
  }
  final base = normalizePackBase(png, onRefused: onRefused);
  if (base == null) return null;
  return (
    bytes: base.bytes,
    width: base.width,
    height: base.height,
    converted: converted,
  );
}
