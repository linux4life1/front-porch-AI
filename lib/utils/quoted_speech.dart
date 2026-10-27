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

/// Removes quoted spoken lines from roleplay prose, leaving the narration.
///
/// Front Porch messages follow the usual convention: `*asterisks*` (or bare
/// prose) narrate, `"quotes"` are what a character SAYS. Two very different
/// features need that distinction and used to answer it separately:
///
/// * the image-prompt builder, so a picture never renders the words of a line
///   of dialogue as literal text;
/// * the story clock's skip net (`mightSkipTime`), so a character
///   *mentioning* a future date does not move the story to it: "will you
///   post a new video next week?" once teleported a real chat seven days
///   forward, twice.
///
/// Straight and curly double quotes both count. Single quotes deliberately do
/// NOT: apostrophes are far more common than single-quoted speech, and
/// treating `don't ... can't` as a quoted span would swallow the narration
/// between them.
///
/// An unterminated quote is left alone — the regex needs a closing mark — which
/// is the conservative direction for both callers: unstripped text keeps the
/// old behaviour rather than silently deleting the rest of a message.
String stripQuotedSpeech(String text) => text
    .replaceAll(RegExp(r'["“][^"”]*["”]'), ' ')
    .replaceAll(RegExp(r'\s{2,}'), ' ')
    .trim();
