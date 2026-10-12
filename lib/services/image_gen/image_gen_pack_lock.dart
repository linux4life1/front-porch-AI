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

import 'package:front_porch_ai/services/image/image.dart';

import 'image_gen_clients.dart';
import 'image_gen_status.dart';

/// Expression packs and stopping a job: one pack holds the generation lock
/// for all of its frames, so nothing else can start between two of them.
class ImageGenPackLock {
  ImageGenPackLock(this._status, this._clients);

  final ImageGenStatus _status;
  final ImageGenClients _clients;

  /// True while a pack holds the lock.
  bool get inFlight => _status.packFlight;

  /// Runs one pack inside a single hold of the generation lock. Null (and the
  /// status says "Already generating.") when a generation is already
  /// running, without calling [driver].
  Future<List<String>?> start(
    List<String> emotions,
    Future<List<String>> Function(List<String> emotions) driver,
  ) async {
    if (_status.isGenerating) {
      _status.say(kAlreadyGeneratingMessage);
      return null;
    }
    _clients.comfyOrNull?.clearCancel();
    _status.packFlight = true;
    _status.isGenerating = true;
    _status.say('Expression pack');
    try {
      return await driver(List<String>.from(emotions));
    } finally {
      // A cancel asked of the picture that was in flight ends with the pack.
      _clients.comfyOrNull?.clearCancel();
      _status.packFlight = false;
      _status.isGenerating = false;
      _status.say('');
    }
  }

  /// Whether a cancel is still waiting for the next ComfyUI post; for tests.
  bool get comfyCancelIsPending =>
      _clients.comfyOrNull?.cancelIsPending ?? false;

  /// Stops the job the server is running: on ComfyUI the prompt is taken off
  /// the queue or interrupted. The other backends have no job to stop from
  /// here; they finish the picture they are on.
  Future<void> cancel() async {
    await _clients.comfyOrNull?.cancelRun(beforePost: _status.isGenerating);
  }
}
