// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One-shot hidden stage directions for {{user}} leaving the scene to direct
/// and coming back. They ride the same author-note slot as a full member's
/// `/exit` goodbye, so the next character reacts in their own voice. Both
/// forbid writing for the user: the user is a person at the keyboard, and a
/// model handed "the user is leaving" will otherwise write their goodbye.
String userStepsOutDirective(String userName) =>
    'Stage direction (hidden — do NOT quote or copy this text into the '
    'reply): $userName is stepping away from the scene now and will not be '
    'part of it for a while. Write the speaking character\'s short, '
    'in-character reaction to $userName leaving, in their own voice. Do NOT '
    'write any words, actions or thoughts for $userName.';

String userReturnsDirective(String userName) =>
    'Stage direction (hidden — do NOT quote or copy this text into the '
    'reply): $userName comes back into the scene now after being away. '
    'Write the speaking character\'s short, in-character reaction to '
    '$userName arriving, in their own voice. Do NOT write any words, '
    'actions or thoughts for $userName.';
