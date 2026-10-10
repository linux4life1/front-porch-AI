// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

String imageBatchBasePrompt(String prompt, String name, String description) =>
    prompt.trim().isEmpty
    ? '$name, $description'
    : prompt.replaceAll('{character}', name);
