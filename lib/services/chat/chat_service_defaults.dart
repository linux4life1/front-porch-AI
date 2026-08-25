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

part of '../chat_service.dart';

// Default system prompts + the needs-critical-threshold forward, hoisted to
// LIBRARY TOP LEVEL (not class statics) as part of the round-4b god-file
// shrink (docs/design/god-file-elimination.md). These were previously
// `static const` / `static` members on ChatService; none of them are part of
// any test fake's interface (statics can't be `@override`d anyway), so moving
// them out of the class body — and every call site from `ChatService.xxx` to
// the bare `xxx` — is a pure relocation with zero behaviour change. Values are
// byte-identical to their old class-static form. `services.dart` exports
// `chat_service.dart`, so callers already importing the services barrel see
// these automatically.

/// Default system prompt for group chats, designed to prevent characters
/// from speaking for each other and maintain turn discipline.
const String defaultGroupSystemPrompt =
    'You are roleplaying in a multi-character group conversation. '
    'CRITICAL RULES:\n'
    '1. You MUST only write dialogue and actions for the character whose turn it is (indicated after <START>). '
    'NEVER write dialogue, thoughts, or actions for other characters or {{user}}.\n'
    '2. Stay fully in character \u2014 use the speaking character\'s unique voice, mannerisms, personality, and speech patterns.\n'
    '3. Keep your response focused on ONE character\'s contribution. Do not narrate what other characters do or say.\n'
    '4. React naturally to what other characters and {{user}} have said. Reference their words, but do not put words in their mouths.\n'
    '5. Write in the style of collaborative roleplay: use *asterisks* for actions/narration and regular text for dialogue.\n'
    '6. Keep responses concise and punchy \u2014 leave room for the next character to respond.\n'
    '7. Never break character or reference the fact that you are an AI.';

/// System prompt for Observer Mode — characters interact with each other, user is not present.
const String observerModeSystemPrompt =
    'You are roleplaying in a multi-character group conversation. '
    'The user is NOT a participant in this story — they are an invisible observer/director. '
    'CRITICAL RULES:\n'
    '1. You MUST only write dialogue and actions for the character whose turn it is. '
    'NEVER write for other characters.\n'
    '2. Characters should interact naturally WITH EACH OTHER — address other characters by name, '
    'respond to what they said, react to their actions. Build on the conversation organically.\n'
    '3. Stay fully in character — use the speaking character\'s unique voice and personality.\n'
    '4. If a [Director] note appears, follow its guidance to steer the scene (introduce new topics, '
    'create conflict, have a character enter/leave, etc.) but do NOT acknowledge the director directly.\n'
    '5. Write in collaborative roleplay style: *asterisks* for actions, regular text for dialogue.\n'
    '6. Keep responses concise — leave room for the next character to respond.\n'
    '7. Never break character or reference being an AI.\n'
    '8. Characters may naturally address each other, start side conversations, argue, agree, '
    'tell stories, ask questions, or react emotionally — make the conversation feel alive and dynamic.';

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
    'feelings directly ("she clenched her jaw" not "she felt angry").\n'
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
    '- Use regular text for speech: "Like this," she said.\n'
    '- Use *asterisks* for actions and narration: *She leaned against the doorframe, arms crossed.*\n'
    '- Internal thoughts can be written in italics or described through narration.';

// Forwarding for critical threshold (moved to NeedsSimulation after buffer removal; UI + cards still reference the old ChatService surface)
int get needCriticalThreshold => NeedsSimulation.needCriticalThreshold;

// The three tuning constants below are the same "private static -> library
// top-level" move as the consts above, swept in during round 4b: each was a
// `static const` on ChatService referenced from other part files as
// `ChatService._xxx`, which is exactly what this technique targets. Still
// library-private (leading underscore) — nothing outside chat_service.dart's
// library ever referenced them, so this is a purely internal rename.

/// Run a cast-detection scan every this-many primary (user) turns. Small and
/// constant so the eval is infrequent and turns stay cheap.
const int _castScanInterval = 4;

/// Streaming-notify coalescing window (~30 fps). See the "Streaming rebuild
/// throttle" comment on `_lastStreamNotify`/`_streamNotifyTimer` in the class
/// body for the full rationale — those two fields stay put; only this const
/// (formerly a co-located `static const`) moved.
const Duration _kStreamNotifyInterval = Duration(milliseconds: 33);

/// Inter-call delay used when staggering the multi-call realism evaluations.
const _kEvalDispatchStagger = Duration(milliseconds: 50);

/// Message-metadata key holding the spatial stance the turn STARTED from.
///
/// Posture is written AFTER generation (it reads the reply), so the message's
/// `realism_state` snapshot — captured before generation — gets its
/// `spatialStance` overwritten with where the reply LEFT her. That is correct
/// for every forward reader and destroys the only copy of the value a
/// REGENERATE has to put back, which is why this receipt exists. Written once
/// per message in `_restampRealismSnapshotPostGen`, read once in the regen
/// revert; named here so the two can never drift apart on a typo.
///
/// Sibling of `needs_pre_turn_vector` and `pre_climax_arousal` — the same
/// contract for the two other post-generation writes.
const String kSpatialStancePreTurn = 'spatial_stance_pre_turn';

// Internal flag to signal a cancellation request for realism evaluation.
// This is a file-scope flag to avoid needing to thread state through the
// entire class in this patch, and is reset once the interruption is surfaced
// to the UI.
bool _realismEvalCancelled = false;

/// Bumped by [_invalidateGreetingEval] (selectGreeting, startNewChat,
/// setActiveCharacter, setActiveGroup, loadSession, _loadLastSession,
/// importChatPackage, forkFromMessage) so a
/// late unawaited [_runPostGreetingEval] cannot stomp a later opening.
int _greetingEvalGen = 0;

const Object _kGreetingEvalToken = #_greetingEvalToken;
const Object _kGreetingEvalIndex = #_greetingEvalIndex;

/// Stale when THIS eval's captured token is no longer the live gen.
/// [_invalidateGreetingEval] always bumps [_greetingEvalGen], so a later
/// opening stale-gates the earlier apply without a shared nullable slot.
/// A missing Zone token is not a greeting apply (normal turn evals).
bool _isStaleGreetingEval() {
  final token = Zone.current[_kGreetingEvalToken] as int?;
  if (token == null) return false;
  return token != _greetingEvalGen;
}

/// Set when [_runPostGreetingEval] passes its guards (not skipped solely
/// because [_activeCharacter] is null). Tests prove group unauthored alts
/// reach the eval path.
@visibleForTesting
bool testPostGreetingEvalEntered = false;

// GBNF grammar support for Realism Engine evals (incl. Needs simulation) removed
// in the 0.9.8 clean port. All JSON outputs now rely on regex extraction + stop
// sequences inside _fireLLMEval (no _buildKoboldGrammar, no _kGbnf* consts).

/// Regex matching any `{{macro}}` or `{{macro::args}}` pattern.
/// Used to detect stray unresolved macros in chat history.
final _macroPattern = RegExp(r'\{\{(\w+)(?:::(.+?))?\}\}');
