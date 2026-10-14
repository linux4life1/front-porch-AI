// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import '../image_prompt/image_prompt.dart';

String imageBatchNegativePrompt(String global, String? emotion) => [
  global,
  if (emotion != null) kExpressionNegatives[emotion] ?? '',
].where((text) => text.trim().isNotEmpty).join(', ');

String imageBatchBasePrompt(String prompt, String name, String description) =>
    prompt.trim().isEmpty
    ? '$name, $description'
    : prompt.replaceAll('{character}', name);
