// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Barrel for the chargen pure leaves. Added when AI Enhance made multiple
/// files import 2+ siblings from this directory (the self-extending barrel
/// rule). The `character_gen_*.dart` files are `part of`
/// character_gen_service.dart and must NEVER be exported here.
library;

export 'char_macro.dart';
export 'chat_grounding.dart';
export 'narrative_voice.dart';
export 'enhance_context.dart';
export 'enhance_lorebook_merge.dart';
export 'lorebook_mechanics.dart';
export 'porch_life_identity.dart';
