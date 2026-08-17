// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_glass.dart';
import 'package:front_porch_ai/ui/pages/repository/stoop_identity_sections.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// The share wizard's 18+ lock: the rule, the notice that explains it, and the
// NSFW switch it holds down. All three live together so the affordance and its
// reason can never drift apart (and so the wizard page stops growing).

/// True when the current pick carries an intimate preference, which forces the
/// share's 18+ flag on. [card] is a solo pick; [members] is a group pick's cast.
///
/// Two traps this deliberately avoids:
///  • It is a CONTENT test, never a key-existence test. Every Front Porch card
///    emits `intimate_preferences` unconditionally (character_card.dart), so
///    "does the key exist" would tag the entire catalogue 18+.
///  • It walks every group member. A group's preferences live per member, never
///    at the group root, so a root-only scan is dodged by shipping a character
///    inside a two-member group.
///
/// [stoopPhrases] does the untrusted-JSON coercion (type-checked, bounded,
/// blank-stripped) — the same read the card page uses, so "has some" means the
/// same thing on both surfaces.
bool stoopForcesAdult(CharacterCard? card, List<GroupMember>? members) {
  final fp = card?.frontPorchExtensions;
  if (fp != null && _hasPhrases(fp.intimateInto, fp.intimateNotInto)) {
    return true;
  }
  for (final m in members ?? const <GroupMember>[]) {
    if (_intimateIn(m.frontPorchExtensions?['realism_engine'])) return true;
  }
  return false;
}

/// The same rule read off a BUILT group card — the exact object whose bytes are
/// about to be uploaded.
///
/// The publish path must decide from this and not from the wizard's pre-publish
/// cast read, which is a separate query that swallows its own errors and returns
/// an empty list on failure. An empty list is indistinguishable from a clean
/// cast, so a transient database hiccup would have shipped `nsfw: false`
/// alongside a card that plainly carries intimate preferences — the server then
/// re-tags it and the author is never told, which is the exact surprise the
/// lock banner exists to prevent.
///
/// Both cast lists are walked because both travel in the payload: `members`
/// (typed, from the exporter) and `raw_member_data` (the high-fidelity maps the
/// importer prefers). They agree today; if they ever stop agreeing, the stricter
/// answer is the safe one.
bool stoopGroupCardForcesAdult(GroupCard card) {
  for (final m in card.members) {
    if (stoopForcesAdult(m, null)) return true;
  }
  for (final raw in card.rawMemberData) {
    final ext = raw['extensions'];
    final porch = ext is Map ? ext['front_porch'] : null;
    if (_intimateIn(porch is Map ? porch['realism_engine'] : null)) return true;
  }
  return false;
}

bool _hasPhrases(Object? into, Object? notInto) =>
    stoopPhrases(into).isNotEmpty || stoopPhrases(notInto).isNotEmpty;

/// The intimate pair inside a `realism_engine` blob of unknown shape (a group
/// member's parsed extensions, or a raw exported member map).
bool _intimateIn(Object? realism) {
  final prefs = realism is Map ? realism['intimate_preferences'] : null;
  return prefs is Map && _hasPhrases(prefs['into'], prefs['not_into']);
}

/// The wizard's 18+ flag PLUS the one thing a bare `bool` cannot record: whether
/// the tick is the AUTHOR's or the RULE's.
///
/// Without that distinction the flag is sticky across picks, and sticky in the
/// direction that hurts: pick a character with intimate preferences (forced on),
/// go Back, pick a spotless one, and the force has released — banner gone,
/// switch unlocked — but the `true` it set is still there, so a card with no
/// intimate preferences at all is published 18+ and hidden from everyone who
/// hasn't opted in. The same fix was already made on the hub; this is its twin.
///
/// So: a tick the rule made is WITHDRAWN when the rule stops applying, and a
/// tick the author made SURVIVES a rule that comes and goes.
class StoopAdultFlag {
  /// What gets published. Starts off; an existing post's flag comes in through
  /// [setByAuthor] (it is the author's earlier decision, not the rule's).
  bool value = false;

  /// True only while [value]'s `true` belongs to the rule rather than the author.
  bool _byRule = false;

  /// Re-decide after the selection changed (or after a slow cast load landed).
  /// Call this on EVERY path that can change what is selected — including the
  /// ones with no cast at all, such as picking a place, which is precisely how
  /// a stale forced `true` used to escape.
  void reconcile({required bool forced}) {
    if (forced) {
      if (!value) {
        value = true;
        _byRule = true;
      }
    } else if (_byRule) {
      value = false;
      _byRule = false;
    }
  }

  /// The author moved the switch themselves — from here the value is theirs and
  /// no later release of the rule may take it back.
  void setByAuthor(bool v) {
    value = v;
    _byRule = false;
  }
}

/// Explains why the 18+ switch is held on. Shown on the Content step directly
/// above that switch, and again on Review — the last screen before Submit.
///
/// Wears the completeness panel's shape (outline + left accent strip) so the
/// two notices read as one family, in amber rather than ember: this is a rule
/// being applied, not a mistake being reported.
class StoopAdultLockBanner extends StatelessWidget {
  const StoopAdultLockBanner({super.key});

  @override
  Widget build(BuildContext context) {
    // Flutter forbids borderRadius with non-uniform BorderSide colors — a full
    // uniform outline plus a solid left strip, exactly like the panel above it.
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: stoopAmberSoft(context),
          border: Border.all(
            color: AppColors.stoopAmber.withValues(alpha: 0.55),
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: AppColors.stoopAmber),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lock_outline_rounded,
                            size: 16,
                            color: stoopAmberText(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'This one has to go up as 18+',
                            style: TextStyle(
                              color: stoopCream(context),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'It carries intimate preferences, so I tag the whole '
                        'card 18+ no matter how tame the rest of the writing '
                        'is — and in a group, one member with them is enough.',
                        style: TextStyle(
                          color: stoopCream2(context),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Want it on The Stoop without the 18+ tag? Open it in '
                        'the character editor, clear the “Intimate '
                        'preferences” chips, save, then come back and share.',
                        style: TextStyle(
                          color: stoopMute(context),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The share's 18+ toggle. When [locked] it is disabled (Flutter greys it out,
/// which is the honest affordance) and its subtitle becomes the reason, so the
/// dead control explains itself instead of reading as a bug. It is never
/// hidden — a switch that vanishes is the thing users report as broken.
///
/// [pending] is the group case: the cast lives in its own table, so for the
/// first frames after a group is picked — and, in update mode, for the first
/// frames of the whole wizard, which opens straight onto this step — nobody
/// knows yet whether the rule applies. Rendering an unlocked, OFF switch during
/// that window states the opposite of the truth and then snaps, so the control
/// says "checking" and stays disabled until the answer is in.
class StoopAdultSwitch extends StatelessWidget {
  final bool value;
  final bool locked;

  /// The cast is still loading, so the rule's answer is not known yet.
  final bool pending;
  final ValueChanged<bool> onChanged;

  const StoopAdultSwitch({
    Key? key,
    required this.value,
    required this.locked,
    this.pending = false,
    required this.onChanged,
  }) : super(key: key ?? const Key('stoop-adult-switch'));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: stoopCardGradient(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stoopBorder(context)),
      ),
      // The gradient must stay on the box, so the tile gets its own
      // transparent Material — ink painted on the nearest Material would
      // otherwise be hidden under the DecoratedBox (Flutter assertion).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: SwitchListTile(
          key: const Key('stoop-adult-switch-tile'),
          value: value,
          onChanged: (locked || pending) ? null : onChanged,
          activeThumbColor: AppColors.stoopEmber,
          title: Text(
            'This content is NSFW (18+)',
            style: TextStyle(color: stoopCream(context)),
          ),
          subtitle: Text(
            pending
                ? 'Checking who’s in this group — one member with intimate '
                      'preferences makes the whole card 18+.'
                : locked
                ? 'Locked on — this one carries intimate preferences, so I '
                      'can’t let it go up as all-ages.'
                : 'Mark adult content so it’s hidden from people who haven’t '
                      'opted in.',
            style: TextStyle(color: stoopMute(context), fontSize: 12),
          ),
        ),
      ),
    );
  }
}
