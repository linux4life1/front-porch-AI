// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Draw Things sampler wire values. One copy. The old private list in
/// `generation_options_tab.advanced.dart` stays until a later slice switches
/// the UI over and deletes that file.
const List<({String label, int value})> kDrawThingsSamplers = [
  (label: 'DDIM Trailing', value: 16),
  (label: 'UniPC Trailing', value: 17),
  (label: 'Euler a Trailing', value: 10),
  (label: 'DPM++ 2M Trailing', value: 15),
  (label: 'DPM++ SDE Trailing', value: 11),
  (label: 'UniPC AYS', value: 18),
  (label: 'Euler a AYS', value: 13),
  (label: 'DPM++ 2M AYS', value: 12),
  (label: 'DPM++ SDE AYS', value: 14),
  (label: 'DPM++ 2M Karras', value: 0),
  (label: 'DPM++ SDE Karras', value: 4),
  (label: 'Euler a', value: 1),
  (label: 'UniPC', value: 5),
  (label: 'DDIM', value: 2),
  (label: 'PLMS', value: 3),
  (label: 'LCM', value: 6),
  (label: 'TCD', value: 9),
  (label: 'Euler a Substep', value: 7),
  (label: 'DPM++ SDE Substep', value: 8),
];
