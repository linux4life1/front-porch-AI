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

/// The three jobs a story's model calls fall into. Each can be pointed at
/// the main model or the worker model per story.
enum StoryRole { planning, prose, review }

/// Thrown inside the pipeline when the user pressed Stop. Never reaches the
/// UI as an error: the outermost operation swallows it.
class StoryStoppedException implements Exception {
  @override
  String toString() => 'Stopped.';
}

/// A stage that could not produce a usable answer. [toString] is the plain
/// message — story pages and the web client show pipeline errors verbatim.
class StoryStageException implements Exception {
  final String message;

  StoryStageException(this.message);

  /// The standard wording when a model keeps answering in a shape the stage
  /// cannot read.
  factory StoryStageException.unreadable(String stage, int attempts) =>
      StoryStageException(
        'The AI\'s answer for "$stage" could not be used after $attempts '
        'tries. This usually means the model is too small for Studio mode. '
        'Try again, switch this story to the Quick engine, or pick the '
        '"Simplified" prompt style.',
      );

  @override
  String toString() => message;
}
