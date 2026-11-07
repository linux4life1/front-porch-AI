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

import 'package:front_porch_ai/services/chat/needs_simulation.dart';

// The chat's default prompts and tuning constants, as library top-level
// names. They were class statics on ChatService, then top-level names in
// one of its part files; the shell exports this library, so every caller
// that imports chat_service.dart still sees them.

/// Cap on active side quests (non-primary). Birthday outings for the
/// character and for {{user}} both need a slot without kicking a quest
/// the user already typed.
const int kMaxSecondaryObjectives = 4;

/// Built-in base prompt for group chats in both modes: style only. The
/// turn and scene rules are FPAI's own (`kGroupSceneRules`,
/// `kDirectorSceneRules`), appended whichever base wins, so a custom Group
/// System Prompt replaces only this part.
const String defaultGroupSystemPrompt =
    '- Write in collaborative roleplay style: *asterisks* for actions and '
    'narration, plain text for dialogue.\n'
    '- Keep each character\'s own voice, manner and way of speaking.\n'
    '- Keep each turn concise and leave room for the next speaker.\n'
    '- Stay in the story. Never mention being an AI.';

/// Default system prompt for local KoboldCPP backends (smaller models).
/// Kept concise so it doesn't eat too much of the limited context window.
const String defaultKoboldSystemPrompt =
    'Write {{char}}\'s next reply in this roleplay with {{user}}. '
    'Stay in character as {{char}} at all times. '
    'Use *asterisks* for actions and narration, regular text for dialogue. '
    'Be creative, descriptive, and drive the scene forward. '
    'Never write actions or dialogue for {{user}}. '
    'Never break character or mention being an AI.';

/// Default system prompt for remote API backends (large cloud models).
/// Highly detailed to leverage the model's full capabilities.
const String defaultApiSystemPrompt =
    'You are an expert collaborative fiction writer and immersive roleplay partner. '
    'You write as {{char}} in an ongoing interactive story with {{user}}.\n\n'
    'CORE IDENTITY:\n'
    '- Embody {{char}} completely. Every response must reflect their unique personality, speech patterns, '
    'vocabulary level, emotional state, and worldview as defined in their character description.\n'
    '- {{char}} is a living, breathing character with their own desires, fears, opinions, and agency \u2014 '
    'not a servant of {{user}}. They can disagree, have bad days, make mistakes, and act according to their own motivations.\n\n'
    'WRITING CRAFT:\n'
    '- Write in a natural, literary style. Vary sentence length and structure. Avoid repetitive sentence openings.\n'
    '- Show emotions through body language, micro-expressions, vocal tone, and subtle actions rather than stating '
    'feelings directly ("they clenched their jaw" not "they felt angry").\n'
    '- Use all five senses \u2014 sight, sound, smell, touch, taste \u2014 to create vivid, immersive scenes.\n'
    '- Dialogue should feel natural and conversational. Characters can interrupt, trail off, use contractions, '
    'stumble over words, or speak in fragments when emotionally charged.\n'
    '- Weave internal thoughts, environmental details, and physical sensations into responses to create depth.\n'
    '- Match the tone and pacing to the scene: tense moments get short, punchy prose; reflective moments get '
    'slower, more lyrical writing.\n\n'
    'ANTI-SLOP RULES \u2014 AVOID THESE CLICH\u00c9S:\n'
    '- Do NOT use: "a symphony of", "a dance of", "sent shivers down", "electricity coursed through", '
    '"breath hitched", "pupils dilated", "orbs" (for eyes), "ministrations", "mewled", '
    '"the air crackled with", "a masterpiece of", "elicited a moan".\n'
    '- Do NOT start responses with: "I", a sigh, a chuckle, or raising an eyebrow.\n'
    '- Do NOT use purple prose or melodramatic narration. Keep descriptions grounded and specific.\n'
    '- Vary your emotional vocabulary \u2014 don\'t repeat the same descriptors across responses.\n\n'
    'RESPONSE GUIDELINES:\n'
    '- Write 2-5 paragraphs per response unless the scene calls for shorter exchanges.\n'
    '- Always advance the scene meaningfully. Each response should move the story forward through action, '
    'revelation, or emotional development.\n'
    '- End responses at natural pause points that invite {{user}} to react \u2014 don\'t resolve conflicts or '
    'answer your own questions.\n'
    '- Never narrate {{user}}\'s actions, thoughts, dialogue, or emotional reactions. Their agency is sacred.\n'
    '- Never break the fourth wall, mention being an AI, or reference the roleplay as fiction.\n'
    '- Maintain continuity with all previously established facts, character history, and world details.\n\n'
    'DIALOGUE FORMAT:\n'
    '- Use regular text for speech: "Like this," they said.\n'
    '- Use *asterisks* for actions and narration: *They leaned against the doorframe, arms crossed.*\n'
    '- Internal thoughts can be written in italics or described through narration.';

/// The Needs bands, read through [NeedsSimulation] (UI and cards still name
/// them here).
int get needCriticalThreshold => NeedsSimulation.needCriticalThreshold;
int get needUrgentThreshold => NeedsSimulation.needUrgentThreshold;

/// Run a cast-detection scan every this-many primary (user) turns. Small and
/// constant so the eval is infrequent and turns stay cheap.
const int kCastScanInterval = 4;

/// Streaming-notify coalescing window (~30 fps); see the streaming rebuild
/// throttle beside `_lastStreamNotify` in the ChatService field bag.
const Duration kStreamNotifyInterval = Duration(milliseconds: 33);

/// Inter-call delay used when staggering the multi-call realism evaluations.
const Duration kEvalDispatchStagger = Duration(milliseconds: 50);
