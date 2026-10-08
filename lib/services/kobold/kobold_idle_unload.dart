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

// "Free the graphics memory when KoboldCpp sits idle": the choices and the
// words the app says about it. The clock itself is KoboldService's
// (kobold_service_idle.dart).

/// Minutes the app's KoboldCpp may sit idle before its model is unloaded to
/// free the graphics memory: 0 (off, the default), 10, 30 or 60.
const List<int> kKoboldIdleUnloadChoices = [0, 10, 30, 60];

/// One of [kKoboldIdleUnloadChoices] as Settings names it.
String koboldIdleUnloadLabel(int minutes) => switch (minutes) {
  0 => 'Off',
  60 => '1 hour',
  _ => '$minutes min',
};

/// The status line once the model has been unloaded.
String koboldIdleUnloadedWords(int minutes) =>
    'The model was unloaded after $minutes idle minutes to free graphics '
    'memory. It loads again with your next message.';

/// The status line while it loads again.
String koboldIdleLoadingWords(String model) => 'Loading $model again…';

/// What a request says when the model could not be loaded again.
String koboldIdleWakeFailedWords(String model) =>
    '$model was unloaded to free graphics memory and could not be loaded '
    'again. If another program is using the graphics memory, close it and '
    'send again; if not, restart KoboldCpp in Settings → Backend.';
