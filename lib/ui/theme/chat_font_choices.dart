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

/// The chat font choices: curated chat-suitable Google Fonts, in picker
/// order. The empty family is "same as the UI font". One list, because the
/// desktop dropdown, the web Settings select and the wire's validation must
/// agree — a family the picker offers but the writer refuses would look
/// accepted and do nothing.
const List<(String, String)> kChatFontChoices = [
  ('Same as the UI font', ''),
  ('Roboto', 'Roboto'),
  ('Open Sans', 'Open Sans'),
  ('Lato', 'Lato'),
  ('Source Sans 3', 'Source Sans 3'),
  ('Nunito', 'Nunito'),
  ('Poppins', 'Poppins'),
  ('Montserrat', 'Montserrat'),
  ('Raleway', 'Raleway'),
  ('Work Sans', 'Work Sans'),
  ('DM Sans', 'DM Sans'),
  ('Quicksand', 'Quicksand'),
  ('Rubik', 'Rubik'),
  ('Karla', 'Karla'),
  ('Merriweather', 'Merriweather'),
  ('Playfair Display', 'Playfair Display'),
  ('Roboto Mono', 'Roboto Mono'),
  ('Fira Code', 'Fira Code'),
];

/// Whether [family] is a choice this build offers ('' included).
bool isChatFontFamily(String family) =>
    kChatFontChoices.any((choice) => choice.$2 == family);
