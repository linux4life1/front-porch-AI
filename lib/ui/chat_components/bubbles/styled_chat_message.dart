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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';

import 'package:front_porch_ai/ui/widgets/styled_text_controller.dart';
import 'external_image_widget.dart';

/// Applies a font family to a base TextStyle dynamically.
/// Uses Google Fonts for web-hosted fonts, otherwise applies system fonts directly.
TextStyle _applyGoogleFont(String? fontFamily, TextStyle baseStyle) {
  if (fontFamily == null || fontFamily.isEmpty) return baseStyle;

  switch (fontFamily) {
    case 'Roboto':
      return GoogleFonts.roboto(textStyle: baseStyle);
    case 'Open Sans':
      return GoogleFonts.openSans(textStyle: baseStyle);
    case 'Lato':
      return GoogleFonts.lato(textStyle: baseStyle);
    case 'Source Sans 3':
      return GoogleFonts.sourceSans3(textStyle: baseStyle);
    case 'Nunito':
      return GoogleFonts.nunito(textStyle: baseStyle);
    case 'Poppins':
      return GoogleFonts.poppins(textStyle: baseStyle);
    case 'Montserrat':
      return GoogleFonts.montserrat(textStyle: baseStyle);
    case 'Raleway':
      return GoogleFonts.raleway(textStyle: baseStyle);
    case 'Work Sans':
      return GoogleFonts.workSans(textStyle: baseStyle);
    case 'DM Sans':
      return GoogleFonts.dmSans(textStyle: baseStyle);
    case 'Quicksand':
      return GoogleFonts.quicksand(textStyle: baseStyle);
    case 'Rubik':
      return GoogleFonts.rubik(textStyle: baseStyle);
    case 'Karla':
      return GoogleFonts.karla(textStyle: baseStyle);
    case 'Merriweather':
      return GoogleFonts.merriweather(textStyle: baseStyle);
    case 'Playfair Display':
      return GoogleFonts.playfairDisplay(textStyle: baseStyle);
    case 'Roboto Mono':
      return GoogleFonts.robotoMono(textStyle: baseStyle);
    case 'Fira Code':
      return GoogleFonts.firaCode(textStyle: baseStyle);
    case 'Source Code Pro':
      return GoogleFonts.sourceCodePro(textStyle: baseStyle);
    // System fonts — apply as named fontFamily directly
    case 'serif':
      return baseStyle.copyWith(fontFamily: 'Times New Roman');
    case 'sans-serif':
      return baseStyle.copyWith(fontFamily: 'Arial');
    case 'monospace':
      return baseStyle.copyWith(fontFamily: 'Courier New');
    default:
      return baseStyle.copyWith(fontFamily: fontFamily);
  }
}

final _markdownImageRegex = RegExp(r'!\[([^\]]*)\]\((https?://[^)]+)\)');

/// Styled chat message with quote/action coloring and external image support.
/// Extracted verbatim (public rename).
class StyledChatMessage extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool? externalImagesAllowed;
  final Future<bool> Function()? onRequestImagePermission;
  final CharacterCard? character;
  final ChatThemePreset? themePreset;
  final ChatThemeOverrides? themeOverrides;

  const StyledChatMessage({
    super.key,
    required this.text,
    required this.isUser,
    this.externalImagesAllowed,
    this.onRequestImagePermission,
    this.character,
    this.themePreset,
    this.themeOverrides,
  });

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final scaledSize = 14.0 * storageService.textScale;

    // Check for markdown images
    final imageMatches = _markdownImageRegex.allMatches(text).toList();
    if (imageMatches.isEmpty) {
      // No images — use existing fast path
      return _buildStyledText(
        context, text, scaledSize, character,
        themePreset: themePreset, themeOverrides: themeOverrides,
      );
    }

    // Split text into segments: [text, image, text, image, text]
    final widgets = <Widget>[];
    int lastEnd = 0;

    for (final match in imageMatches) {
      // Text before this image
      if (match.start > lastEnd) {
        final textBefore = text.substring(lastEnd, match.start).trim();
        if (textBefore.isNotEmpty) {
          widgets.add(
            _buildStyledText(
              context, textBefore, scaledSize, character,
              themePreset: themePreset, themeOverrides: themeOverrides,
            ),
          );
        }
      }

      final altText = match.group(1) ?? '';
      final imageUrl = match.group(2)!;

      // Image placeholder or loaded image
      widgets.add(
        ExternalImageWidget(
          url: imageUrl,
          altText: altText,
          allowed: externalImagesAllowed,
          onRequestPermission: onRequestImagePermission,
        ),
      );

      lastEnd = match.end;
    }

    // Remaining text after last image
    if (lastEnd < text.length) {
      final textAfter = text.substring(lastEnd).trim();
      if (textAfter.isNotEmpty) {
        widgets.add(
          _buildStyledText(
            context, textAfter, scaledSize, character,
            themePreset: themePreset, themeOverrides: themeOverrides,
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildStyledText(
    BuildContext context,
    String segment,
    double scaledSize,
    CharacterCard? character, {
    ChatThemePreset? themePreset,
    ChatThemeOverrides? themeOverrides,
  }) {
    final storageService = Provider.of<StorageService>(context);
    final fontFamily = storageService.getChatFontFamily(
      character, themePreset, themeOverrides,
    );
    final textColor = isUser
        ? storageService.getUserTextColor(
            character, themePreset, themeOverrides,
          )
        : storageService.getAiTextColor(
            character, themePreset, themeOverrides,
          );
    final plainStyle = _applyGoogleFont(
      fontFamily,
      TextStyle(color: textColor, fontSize: scaledSize),
    );
    final dialogueStyle = _applyGoogleFont(
      fontFamily,
      TextStyle(
        color: storageService.getDialogueColor(
          character,
          themePreset,
          themeOverrides,
        ),
        fontWeight: FontWeight.w500,
        fontSize: scaledSize,
      ),
    );
    final actionStyle = _applyGoogleFont(
      fontFamily,
      TextStyle(
        color: storageService.getActionColor(
          character,
          themePreset,
          themeOverrides,
        ),
        fontSize: scaledSize,
      ),
    );

    final tokens = tokenizeChat(segment);

    final spans = <TextSpan>[];
    int lastEnd = 0;
    for (final t in tokens) {
      if (t.start > lastEnd) {
        spans.add(TextSpan(
          text: segment.substring(lastEnd, t.start),
          style: plainStyle,
        ));
      }
      spans.add(TextSpan(
        text: t.matchText,
        style: t.type == StyledTokenType.dialogue ? dialogueStyle : actionStyle,
      ));
      lastEnd = t.end;
    }
    if (lastEnd < segment.length) {
      spans.add(TextSpan(
        text: segment.substring(lastEnd),
        style: plainStyle,
      ));
    }

    if (spans.isEmpty) {
      return SelectionArea(
        child: Text(
          segment,
          style: _applyGoogleFont(
            fontFamily,
            TextStyle(color: textColor, fontSize: scaledSize, height: 1.4),
          ),
        ),
      );
    }

    return SelectionArea(
      child: RichText(
        text: TextSpan(
          style: _applyGoogleFont(
            fontFamily,
            TextStyle(color: textColor, fontSize: scaledSize, height: 1.4),
          ),
          children: spans,
        ),
      ),
    );
  }
}
