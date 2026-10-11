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

import 'package:flutter/foundation.dart';

/// Plain (non-ChangeNotifier) domain service owning the Chaos Mode / Chance Time
/// state and logic (pressure gauge growth + auto-trigger roll, event pools,
/// spin sampling, apply with {{char}} replacement + injection + metadata side effect,
/// clear timing via delivered flag).
///
/// ChatService owns the instance via a private late final and delegates. All cross
/// state that lives in the parent for now (pendingRealismMetadata for the delta chip)
/// is accessed exclusively via callbacks supplied at construction. This keeps the
/// extracted service testable and avoids cycles. (Granular callbacks chosen over a
/// full parent interface ref for this leaf extraction per the Stage 3 precedent and
/// updated plan guidance in refactoring-guide.md.)
///
/// UI-coordination state that crosses widget boundaries (_chanceTimeCompleter for
/// pausing sendMessage during wheel, _chanceTimePendingTrigger for overlay pop,
/// _pendingChanceTimeEvent display value) remains in ChatService. The service owns
/// the pure sim core (enabled, nsfw, pressure, pendingInjection for prompt, delivered flag).
///
/// Extraction is mechanical: original methods/fields/consts/pools copied verbatim
/// (pressure math, microsecondsSinceEpoch % 100 roll, shuffle/take(8), NSFW conditional,
/// replace in apply, delivery flag timing for clear-on-next, group/chat-scoped pressure).
/// No behavior changes. Group vs 1:1 parity preserved (chat-scoped pressure + enabled
/// from group def or per-char ext seed; {{char}} replaced by current speaker at apply time).
///
/// Callbacks: onNotify (for UI refresh after apply), onSaveChat (persist scalars),
/// onSetPendingRealismMetadata (for the 'chance_time_event' chip delta).
class ChaosModeService {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;
  final void Function(String key, String value) onSetPendingRealismMetadata;

  // Owned simulation state (moved verbatim from ChatService).
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false; // include spicy/NSFW events in the pool
  int _chaosPressure = 0; // 0–100; grows each turn without a trigger
  String?
  _pendingChaosInjection; // event text to inject into the next response prompt
  bool _chaosEventDelivered =
      false; // true after the event has been used in at least one generation

  ChaosModeService({
    required this.onNotify,
    required this.onSaveChat,
    required this.onSetPendingRealismMetadata,
  });

  // ── Public surface (for shims in ChatService + direct test/UI callers) ──────

  bool get chaosModeEnabled => _chaosModeEnabled;
  bool get chaosNsfwEnabled => _chaosNsfwEnabled;
  int get chaosPressure => _chaosPressure;

  /// True if there is a Chance Time event prepared for the *next* response
  /// generation that has not yet been delivered.
  ///
  /// Once the injection has been consumed (markEventDelivered called from the
  /// prompt builder), this returns false. This lets the UI (Chaos sidebar
  /// "⏳ EVENT PENDING" state + disabled spin) clear as soon as the character
  /// has received the event in their prompt — even though the raw value + delivered
  /// flag are kept so that regens/swipes of the reacting AI message can still
  /// re-inject the same event.
  ///
  /// The actual value is only fully cleared on the *next* user turn via
  /// clearDeliveredPendingIfAny (preserving the "until user sends new message"
  /// regen window from the original design).
  bool get hasPendingChaosEvent =>
      _pendingChaosInjection != null && !_chaosEventDelivered;

  // Internal accessors for the prompt injection getter (which stays in ChatService
  // until prompt_injection/ subdir extraction in step 8).
  String? get pendingChaosInjection => _pendingChaosInjection;
  bool get chaosEventDelivered => _chaosEventDelivered;

  // Canonical consts (single source of truth; previously private in god file).
  static const int baseChance = 5;
  static const int growthPerTurn = 5;
  static const int pressureCap = 100;

  // ── Chance Time Event Pool (120 events) — moved verbatim, now public static ──

  static const List<String> chanceTimeEventPool = [
    // 🟢 Fortune — lucky breaks, good vibes, unexpected wins
    '{{char}} just found something valuable they completely forgot they owned',
    '{{char}} was mistaken for someone important and is being treated accordingly',
    '{{char}} stumbled into a crowd of admirers who are totally convinced they are famous',
    'Something {{char}} lost a long time ago has just turned up in the most unexpected place',
    '{{char}} received a completely unexpected compliment that made their entire day',
    '{{char}} just discovered a hidden stash of food or treats at exactly the right moment',
    '{{char}} pulled off something impressive entirely by accident and everyone thinks it was intentional',
    'A stranger just paid for {{char}}\'s meal or expenses without any explanation',
    '{{char}} arrived somewhere late only to discover being late was absolutely the right call',
    '{{char}} just found out they won something they entered and completely forgot about',
    'An incredibly beautiful view or spectacle has appeared right where {{char}} is standing',
    '{{char}} accidentally said the perfect thing at the perfect moment',
    '{{char}} is having the best hair or appearance day of their life today',
    'Something that was going terribly for {{char}} has inexplicably turned completely around',
    '{{char}} discovered a shortcut or trick that makes everything significantly easier',
    '{{char}} just got offered a seat, a table, or a spot that would normally go to someone far more important',
    'The weather turned absolutely perfect the moment {{char}} stepped outside',
    '{{char}} ran into someone they\'ve been hoping to bump into for a long time',
    'An animal has taken an immediate and enthusiastic liking to {{char}}',
    '{{char}} made a guess that turned out to be completely correct',
    '{{char}} just overheard something that is extremely good news for them',
    'Someone has arrived to help {{char}} with exactly the thing they were struggling with',
    '{{char}} was offered more than they asked for and no one is sure why',
    'A small act of kindness {{char}} performed long ago has just come back around in a big way',
    '{{char}} woke up unusually well-rested and is in an extremely good mood for no particular reason',
    '{{char}} got the best seat, the best portion, or the best version of the thing',
    '{{char}} just accomplished something they\'ve been attempting for a very long time',
    'Everyone in the room seems to be finding {{char}} particularly charming today',
    '{{char}} discovered someone nearby has been quietly rooting for them this whole time',
    '{{char}} received unexpected credit for something that worked out really well',
    // 🔴 Misfortune — embarrassing, gross, inconvenient, funny
    '{{char}} urgently needs to use the restroom and there is no good option available',
    '{{char}} just stepped in something extremely unpleasant and is now tracking it everywhere',
    '{{char}} sneezed violently at the absolute worst possible moment',
    '{{char}} sat in something wet and has no idea how to address this situation',
    '{{char}} has the hiccups and they won\'t stop no matter what',
    '{{char}} just bit their tongue so hard they can barely form words',
    '{{char}} has been walking around with something in their teeth for an unknown amount of time',
    '{{char}}\'s clothing has ripped in an extremely inconvenient location',
    '{{char}} knocked something over in the loudest and most attention-grabbing way possible',
    '{{char}} tripped, caught themselves, but everyone absolutely saw it',
    '{{char}} let out an involuntary sound at the most inopportune moment imaginable',
    '{{char}} is extremely itchy somewhere they cannot scratch in polite company',
    '{{char}} just spilled something on themselves and is pretending it didn\'t happen',
    '{{char}}\'s stomach is making alarming sounds at the worst possible time',
    '{{char}} said goodbye to someone and then walked in the same direction as them',
    '{{char}} confidently greeted someone who has no idea who they are',
    '{{char}} waved back at someone who was not actually waving at them',
    '{{char}} laughed at something completely inappropriate and now can\'t stop',
    '{{char}} walked into something that was very clearly visible',
    '{{char}} has a piece of hair or debris stuck somewhere they can\'t remove it without help',
    '{{char}} woke up with a spectacular and inexplicable mark on their face',
    '{{char}} is dealing with a persistent and loudly squeaking piece of their clothing or equipment',
    '{{char}} just yawned enormously in front of exactly the wrong person',
    '{{char}} sent a message and immediately regretted every single word of it',
    '{{char}} is trying to pretend they remember the name of someone they absolutely do not',
    '{{char}}\'s hands are completely full at exactly the moment they desperately need a free hand',
    '{{char}} dropped something and it rolled to the most awkward possible location',
    '{{char}} got something in their eye at the worst possible time',
    '{{char}} has been nodding along in a conversation they stopped following ten minutes ago',
    '{{char}} just realized they\'ve been pronouncing something wrong their entire life',
    '{{char}} is having a sneezing fit and it is not going to stop anytime soon',
    '{{char}} just made direct and sustained eye contact with someone during an extremely awkward moment',
    '{{char}} reached for something confidently and missed completely',
    '{{char}} fell asleep briefly somewhere very inappropriate',
    '{{char}} made a very confident prediction that was immediately and publicly proven wrong',
    '{{char}} went to tell a story and completely forgot where it was going halfway through',
    '{{char}} is having the most stubborn and uncooperative hair day of their life',
    '{{char}} just let out an involuntary noise while trying to lift something heavy',
    '{{char}} immediately regretted the food choice they were so confident about',
    '{{char}} is dealing with a shoe, boot, or footwear issue that keeps demanding attention',
    '{{char}}\'s name has been mispronounced repeatedly and they\'ve been too polite to correct it',
    '{{char}} just realized they\'ve had something on backwards or inside-out all day',
    // 💛 Chaos — strange, unpredictable, and completely out of nowhere
    'A bird flew directly into the space {{char}} is in and absolutely refuses to leave',
    'An incredibly loud and disruptive noise has started nearby with no explanation',
    'Something nearby fell over on its own for no apparent reason whatsoever',
    '{{char}} has become the unexpected center of a very enthusiastic and confusing celebration',
    'A small animal has decided that {{char}}\'s belongings are now its home',
    'A person in an extremely unusual outfit has just walked by and is completely serious',
    'Everything that could make noise in {{char}}\'s vicinity is making noise simultaneously',
    'A sudden and powerful gust of wind has created a chaotic situation involving {{char}}\'s belongings',
    'An extremely large insect has appeared and is refusing to be dealt with',
    'The lighting wherever {{char}} is has done something extremely unexpected',
    'A crowd has formed nearby for reasons that remain completely unclear',
    'Someone nearby is telling a very loud and very one-sided story that involves {{char}} by name',
    'A persistent and enthusiastic child or small creature has fixated entirely on {{char}}',
    'Something is cooking or burning nearby and the smell is completely overwhelming',
    'A piece of {{char}}\'s environment has broken in a way that is more funny than serious',
    'An uninvited guest or creature has appeared and made themselves entirely at home',
    '{{char}}\'s surroundings have spontaneously rearranged themselves in a confusing way',
    'A very confident stranger is trying to recruit {{char}} into something on the spot',
    'Two other people nearby have begun a surprisingly loud and personal argument',
    'Something small and ridiculous has escalated into a situation requiring everyone\'s attention',
    'A nearby animal is doing exactly what it should not be doing and nobody can stop it',
    '{{char}} has accidentally started a trend and people nearby are copying them',
    'Someone nearby is performing something unsolicited and making eye contact with {{char}}',
    'The rhythm of everything around {{char}} has synchronized into something inexplicably musical',
    'A delivery or package has arrived for {{char}} with completely incorrect contents',
    'Something that was definitely fixed has become unfixed again at the worst time',
    'An object nearby has developed a squeak, rattle, or wobble that cannot be ignored',
    '{{char}} is in the middle of a very long and intricate process when something interrupts everything',
    'Every seat, surface, or resting spot nearby is occupied or unavailable',
    'Something {{char}} was counting on to work fine has decided today is not that day',
    // 💜 Wild Cards — character-specific fun situations
    '{{char}} is absolutely starving and trying very hard not to let it show',
    '{{char}} has a song stuck in their head that keeps making them move involuntarily',
    '{{char}} is desperately trying to stay awake and losing the battle',
    '{{char}} just thought of a really good comeback to something that happened hours ago',
    '{{char}} is trying to look like they know what they\'re doing in a situation they definitely do not',
    '{{char}} has been holding in a laugh for so long it\'s becoming a physical problem',
    '{{char}} is running on absolutely no sleep and extremely committed to pretending otherwise',
    '{{char}} is convinced something delicious is nearby but can\'t figure out where it\'s coming from',
    '{{char}} just thought of something embarrassing from years ago completely unprompted',
    '{{char}} is trying to remember something very important and it is right on the tip of their tongue',
    '{{char}} is putting in extraordinary effort to appear calm about something that is stressing them out enormously',
    '{{char}} is extremely competitive about something that absolutely does not warrant it',
    '{{char}} has been daydreaming so intensely they\'ve lost track of what\'s happening around them',
    '{{char}} has made a small purchase or decision they are now deeply second-guessing',
    '{{char}} is trying very hard not to react to something that is extremely funny to them right now',
    '{{char}} strongly suspects they are being pranked and is watching everyone very carefully',
    '{{char}} is operating at an unusually high level of confidence today for no specific reason',
    '{{char}} has a strong opinion about something minor and is barely keeping it to themselves',
    '{{char}} is lowkey obsessed with a very small and inconsequential detail in their environment',
    '{{char}} just caught themselves doing something weird and hopes nobody noticed',
    '{{char}} is absolutely convinced they\'re forgetting something but cannot figure out what',
    '{{char}} has developed an instant and irrational dislike of a completely harmless object nearby',
    '{{char}} just said something they think was smooth and they\'re very pleased with themselves',
    '{{char}} is being incredibly polite about something they find deeply annoying',
    '{{char}} is trying to subtly fix an error they made without drawing attention to it',
    '{{char}} is losing a silent battle with their posture',
    '{{char}} has a very specific craving that is now impossible to stop thinking about',
    '{{char}} just finished something they were putting off for a long time and feels unreasonably good',
    '{{char}} is distracted by an extremely irrelevant but very interesting thing happening nearby',
    '{{char}} is holding a very strong opinion hostage and it is getting increasingly difficult',
    // 🎪 Slapstick — physical comedy, chaotic energy
    'Someone set off a stink bomb nearby and {{char}} is directly in the blast zone',
    '{{char}}\'s pants, skirt, or equivalent just fell down in the most public setting imaginable',
    '{{char}} has been glitter-bombed and is now sparkling uncontrollably from every surface',
    '{{char}} got completely and thoroughly soaked by something falling, splashing, or bursting nearby',
    '{{char}} sat on something that made an extremely loud and unfortunate noise in a silent room',
    '{{char}} walked into a door, a pole, or a wall that was extremely clearly there',
    '{{char}} got tangled in something — a rope, a curtain, their own clothing — and is now stuck',
    '{{char}} accidentally flung food at someone important while trying to eat normally',
    '{{char}} sneezed so violently they knocked something over, fell backwards, or both',
    '{{char}} slipped on something wet and went down in slow motion in front of everyone',
    '{{char}} tried to lean casually on something and it moved, sending them stumbling',
    '{{char}} just ripped something open far too aggressively and the contents went everywhere',
    '{{char}} attempted to catch something thrown to them and missed so badly it hit someone else',
    '{{char}}\'s chair, stool, or seat just collapsed underneath them with maximum noise',
    '{{char}} tried to open a container and the lid popped off, launching the contents directly at them',
    '{{char}} walked confidently forward and stepped directly into a puddle, hole, or ditch',
    '{{char}} got hit in the face by something soft, harmless, and deeply undignified',
    'A bucket, bag, or container of something has tipped directly onto {{char}}\'s head',
    '{{char}} grabbed something sticky and now cannot let go without making things worse',
    '{{char}} accidentally knocked over a chain reaction of objects like a line of dominoes',
    '{{char}} tried to do something athletic and it went spectacularly wrong in front of an audience',
    '{{char}} got their hand, foot, or head stuck in something and is now committed to this situation',
    'Someone threw something at {{char}} as a prank and their reaction made everything funnier',
    '{{char}}\'s belt, strap, or buckle just snapped at the worst possible moment',
    '{{char}} is covered in something — paint, mud, ink, flour — and cannot explain how it happened',
  ];

  // ── Chance Time NSFW Pool (only included when 🌶️ toggle is on) — verbatim ───

  static const List<String> chanceTimeNsfwPool = [
    '{{char}} just received an extremely personal delivery in front of other people',
    'A stranger on the street just propositioned {{char}} loudly and confidently in public',
    '{{char}}\'s most private undergarment is now visible and they have not yet realized it',
    '{{char}} accidentally opened something very explicit on a shared or public surface',
    '{{char}} just made a noise that sounded extremely suggestive and now everyone is staring',
    'Someone mistook {{char}} for a worker at a very adult-themed establishment',
    '{{char}} found something very intimate that does not belong to them in their belongings',
    '{{char}} walked into the wrong room and what they saw cannot be unseen',
    '{{char}} scratched somewhere inappropriate and someone absolutely noticed',
    '{{char}} is visibly aroused at the most inconvenient moment imaginable and is scrambling',
    'A stranger just described {{char}} in extremely flattering and very explicit physical terms within earshot',
    '{{char}}\'s clothing has shifted in a way that is revealing something they very much did not intend to share',
    '{{char}} just discovered that a private intimate item of theirs has been on display this whole time',
    'A love letter or extremely personal note written about {{char}} has just been read aloud to the room',
    '{{char}} was caught very obviously checking someone out and both parties know it',
    '{{char}} accidentally grabbed someone in a place that was very much not where they intended',
    'Something {{char}} said came out sounding incredibly dirty and everyone heard it',
    '{{char}} has just received a gift that is unmistakably sexual and has to open it in front of people',
    '{{char}} is trying extremely hard to hide a visible physical reaction to someone attractive nearby',
    '{{char}} walked in on something they desperately wish they had not walked in on',
    'Someone just loudly and publicly asked {{char}} about their love life in excruciating detail',
    '{{char}} realized their private journal or personal writing has been read by someone else',
    '{{char}} is wearing something under their clothes that they would be mortified for anyone to discover',
    'An ex-lover of {{char}} has just appeared and is being very loud about their shared history',
    '{{char}} was dared to do something embarrassingly intimate and is now trapped by their own pride',
    '{{char}} made eye contact with someone attractive at exactly the wrong moment and froze',
    '{{char}} was mistaken for someone\'s lover and the misunderstanding is escalating fast',
    '{{char}} just got caught practicing a flirtatious or seductive pose in what they thought was privacy',
    'A very personal garment belonging to {{char}} has just fallen out of their bag in a crowded space',
    '{{char}} accidentally moaned, groaned, or made a compromising sound while stretching or sitting down',
  ];

  // ── Control / mutation (side-effect free; wrapper in ChatService does save/notify) ──

  void setModeEnabled(bool enabled) {
    _chaosModeEnabled = enabled;
    if (!enabled) _chaosPressure = 0;
  }

  void setNsfwEnabled(bool enabled) {
    _chaosNsfwEnabled = enabled;
  }

  // Direct scalar sets for load/reset sites (kept in sync across multiple call sites in parent).
  void setPressure(int value) {
    _chaosPressure = value;
  }

  void setPendingChaosInjection(String? value) {
    _pendingChaosInjection = value;
  }

  void setEventDelivered(bool value) {
    _chaosEventDelivered = value;
  }

  // ── Reset helpers (support "keep reset blocks in sync" comments in parent without god-file helpers) ──

  void resetForFreshChat() {
    _chaosModeEnabled = false;
    _chaosPressure = 0;
    _pendingChaosInjection = null;
    _chaosEventDelivered = false;
  }

  void seedFromGroupOrExt(bool modeEnabled, bool nsfwEnabled) {
    _chaosModeEnabled = modeEnabled;
    _chaosNsfwEnabled = nsfwEnabled;
    // Pressure left as-is or explicitly zeroed by caller per original reset sites.
  }

  void loadScalars({required bool modeEnabled, required int pressure}) {
    _chaosModeEnabled = modeEnabled;
    _chaosPressure = pressure;
  }

  // ── Actions (verbatim) ─────────────────────────────────────────────────────

  /// Clear the pending *injection* after it has been delivered in a response.
  /// (The display pendingChanceTimeEvent UI flag is managed in ChatService.)
  void clearDeliveredPendingIfAny() {
    if (_chaosEventDelivered) {
      _pendingChaosInjection = null;
      _chaosEventDelivered = false;
    }
  }

  /// Returns 8 randomly-sampled events for the wheel UI to display.
  List<String> spinWheelEvents() {
    final pool = List<String>.from(chanceTimeEventPool);
    if (_chaosNsfwEnabled) pool.addAll(chanceTimeNsfwPool);
    pool.shuffle();
    return pool.take(8).toList();
  }

  /// Core apply logic (pressure zero, injection set, realism metadata via cb, persist/notify).
  /// The caller (ChatService thin wrapper) is responsible for:
  /// - computing the {{char}}-replaced display string (for UI pendingEvent flag)
  /// - setting the UI _pendingChanceTimeEvent
  /// - completing the _chanceTimeCompleter (UI pause coordination)
  Future<void> applyPreparedEvent(String display) async {
    _pendingChaosInjection = display;
    _chaosPressure = 0;

    onSetPendingRealismMetadata('chance_time_event', display);

    await onSaveChat();
    onNotify();
    debugPrint('[ChanceTime] Applied: $display — injecting into next response');
  }

  /// Per-turn auto-trigger check. Returns true if the wheel should pop this turn.
  /// Verbatim roll using microsecondsSinceEpoch % 100 for entropy.
  bool checkAndTickChaosPressure() {
    if (!_chaosModeEnabled) return false;
    _chaosPressure = (_chaosPressure + growthPerTurn).clamp(0, pressureCap);
    final effectiveChance = (baseChance + _chaosPressure).clamp(0, pressureCap);
    // Use microseconds for better entropy than milliseconds
    final roll = (DateTime.now().microsecondsSinceEpoch % 100);
    final fires = roll < effectiveChance;
    if (fires) {
      debugPrint(
        '[ChanceTime] Auto-trigger! pressure=$_chaosPressure% roll=$roll',
      );
    }
    return fires;
  }

  // ── Prompt injection support (for _getChanceTimeInjection which stays in god for step 8) ──

  void markEventDelivered() {
    _chaosEventDelivered = true;
  }
}
