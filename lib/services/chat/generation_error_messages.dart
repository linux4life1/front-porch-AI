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

// User-facing error message mapping for a failed generation turn — extracted
// verbatim from the ChatService generation catch block (god-file ratchet).
// Pure String→String transform: zero ChatService access.

/// Map a raw generation-failure error string (typically `error.toString()`)
/// to a friendlier, actionable message for the chat transcript. Unmapped
/// errors pass through unchanged (minus the stripped `Exception: ` prefix).
String friendlyGenerationError(String rawError) {
  // Strip Dart's "Exception: " prefix for cleaner display
  var errorMsg = rawError.replaceFirst(RegExp(r'^Exception:\s*'), '');

  if (errorMsg.contains('STREAMING_NOT_SUPPORTED') ||
      errorMsg.contains('HTTP 405')) {
    errorMsg =
        'HTTP 405: The server does not support this request. '
        'If streaming is enabled, try disabling it in Settings > Generation Settings. '
        'Also verify your API URL is correct.';
  } else if (errorMsg.contains('Backend process crashed')) {
    errorMsg =
        'The backend crashed (likely out of VRAM). '
        'Try reducing GPU layers or context size in Settings.';
  } else if (errorMsg.contains('not generation-ready') ||
      errorMsg.contains('reload_config')) {
    errorMsg =
        'The worker model did not become ready after the GPU swap. '
        'Chat speech was put back. Try sending again.';
  } else if (errorMsg.contains('timed out') ||
      errorMsg.contains('TimeoutException')) {
    errorMsg =
        'Request timed out. The model may be too large or the server too slow.';
  } else if (errorMsg.contains('Connection closed before full header') ||
      (errorMsg.contains('ClientException') && errorMsg.contains('closed'))) {
    errorMsg =
        'The connection to the backend was closed unexpectedly. '
        'The model may still be loading — wait for the green ready indicator and try again. '
        'If this persists, the backend may have run out of VRAM.';
  }

  return errorMsg;
}

/// Shown when PRE-GEN attached an empty bubble and the mouth stream
/// produced no assistant text (swap unlocked on version 200).
const kEmptySpeechAfterPregenNotice =
    'The character reply came back empty after the model swap. '
    'The model was not ready to generate. Try sending again.';

/// True when a new (non-Continue) speech turn claimed PRE-GEN attach
/// and then produced no text — FAIL, not a successful blank bubble.
bool emptySpeechAfterPregen({
  required String accumulated,
  required bool isContinue,
}) {
  if (isContinue) return false;
  return accumulated.trim().isEmpty;
}
