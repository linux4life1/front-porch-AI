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

/// The post-generation pockets eval + stamps. Intro queue and persist
/// helpers stay on [ChatServicePockets]. Continue [asContinuation] keeps
/// the turn's original `pockets_before`.
extension ChatServicePocketsPass on ChatService {
  /// Runs the detection pass for the speaker who just replied.
  ///
  /// Gated HERE and nowhere else, so there is exactly one place the feature is
  /// switched on. The eval leaf itself consults no settings — that separation
  /// is what stops a second gate appearing somewhere later and disagreeing
  /// with this one.
  ///
  /// [asContinuation]: the Continue button's incremental run — [reply] is the
  /// NEW text only (the first half was bookkept when the reply was first
  /// generated). Ops apply on top of the current record exactly like any
  /// other exchange extension; what changes is the stamps: the message's
  /// existing `pockets_before` is PRESERVED (it holds the turn's true
  /// pre-state — overwriting it with the mid-turn record would make regen
  /// and tail-delete rewind to the middle of the turn), new transfer
  /// recipients union into it, and receipts append instead of replacing.
  Future<void> _runPocketsPass(
    String reply, {
    bool asContinuation = false,
  }) async {
    if (!_storageService.realismSettings.pocketsEnabled) return;
    if (reply.trim().isEmpty) return;

    final speaker = _activeCharacter;
    if (speaker == null) return;
    final charId = _getCharacterIdFromCard(speaker);

    // Seed from the card the first time this chat asks: an author who wrote
    // `frontPorchExtensions.inventory` expects them to START with those things,
    // not to acquire them by accident later.
    // Still `??`-lazy, and still load-bearing: seedPocketsFromCards runs at
    // the top of a user turn, so a character who ARRIVES mid-turn (a Scene
    // Guest, a cast change) reaches this without having been seeded.
    final record = pocketsFor(charId) ?? startingPocketsFor(speaker);
    // Lazy morning housekeeping: yesterday's set-aside clothes leave the
    // record the first time it is touched on a new story day, BEFORE any
    // prompt or op can see them. Possessions stay (see SetAsideItem).
    final day = storyDayCount;
    record.expireSetAside(day);

    // Pre-turn snapshot for the rewind stamps below — taken AFTER expiry on
    // purpose, so a later restore can never resurrect expired clothes.
    final beforeJson = record.toJson();

    // Hand-offs (Porch Life -> "Hand things between characters"). Only ever in
    // a group: in a 1:1 the only other party is the user, who has no record to
    // put anything into, so the roster stays empty and the model is never
    // invited to name a recipient.
    final transfersOn =
        _storageService.realismSettings.pocketTransfersEnabled &&
        _activeGroup != null;
    final others = transfersOn
        ? [
            for (final c in _groupCharacters)
              if (_getCharacterIdFromCard(c) != charId) c.name,
          ]
        : const <String>[];

    // A LIST of (recipient, item), not a map keyed by recipient: "they hand
    // Sam the keys and the letter" is two transfers to one name, and the
    // map silently kept only the last while both receipts claimed delivery
    // (hostile review, 2026-08-11).
    final handedOver = <(String, PocketItem)>[];
    // Resolve against the roster the model was actually shown. An
    // unresolvable name is DROPPED, not guessed: the item still leaves
    // the giver (that much is true either way) and simply reaches
    // nobody, which is the behaviour every build before this one had.
    final onTransfer = transfersOn
        ? (String to, PocketItem item) {
            final match = resolveRecipient(to, others);
            if (match != null) handedOver.add((match, item));
          }
        : null;

    // On a fused reply-facts turn the question was already asked (one call
    // for all three bookkeeping passes) — parse this pass's slice through
    // the SAME parser and applier the standalone call feeds. An answer with
    // no ops is the common case and applies nothing, exactly as today.
    final fused = _replyFactsRaw;
    // Applied-change feed for the item-memory journal cards — populated by
    // the applier with canonical names, consumed after the record persists.
    final events = <PocketEvent>[];
    final List<String> receipts;
    if (fused != null) {
      final ops = PocketsEval.parseOps(fused);
      receipts = ops.isEmpty
          ? const []
          : applyPocketOps(
              record,
              ops,
              onTransfer: onTransfer,
              day: day,
              events: events,
            );
    } else {
      receipts = await _pocketsEval.evaluateAndApply(
        charName: speaker.name,
        pockets: record,
        // Clamped like every judge window (the eval diet missed the
        // bookkeeping passes — a 20k-char novella reply rode this prompt
        // raw, hostile review 2026-08-11).
        reply: clampEvalMessage(reply),
        // Without this a change the USER narrated — walking them out into the
        // rain — is invisible to the eval, and the dress stays recorded dry.
        recentExchange: recentExchange(_messages),
        others: others,
        onTransfer: onTransfer,
        day: day,
        events: events,
      );
    }

    // Apply the arrivals AFTER the giver's own record is settled, so a
    // hand-off can never be read back out of the giver mid-pass.
    // Recipient BEFORE/AFTER snapshots ride the rewind stamp so regen and
    // tail-delete put BOTH sides of a give back (release audit 2026-08-11:
    // only the giver was stamped, so Sam kept the keys after a reject).
    final othersBefore = <Map<String, dynamic>>[];
    final othersAfter = <Map<String, dynamic>>[];
    final seenRecipients = <String>{};
    for (final (to, item) in handedOver) {
      final matches = _groupCharacters.where((c) => c.name == to);
      if (matches.isEmpty) continue;
      final recipient = matches.first;
      final rid = _getCharacterIdFromCard(recipient);
      final theirs = pocketsFor(rid) ?? startingPocketsFor(recipient);
      // One before-snapshot per recipient (multiple items to Sam → one kit).
      if (seenRecipients.add(rid)) {
        othersBefore.add({'char': rid, 'record': theirs.toJson()});
      }
      theirs.carrying.add(item);
      while (theirs.carrying.length > kMaxCarrying) {
        theirs.carrying.removeAt(0);
      }
      setPocketsFor(rid, theirs);
      debugPrint(
        '[Pockets] ${speaker.name} -> ${recipient.name}: ${item.display}',
      );
    }
    for (final ob in othersBefore) {
      final rid = ob['char'] as String;
      final afterRec = pocketsFor(rid);
      if (afterRec != null) {
        othersAfter.add({'char': rid, 'record': afterRec.toJson()});
      }
    }

    // Store even when nothing changed: the first turn is what promotes a
    // card-seeded record into the chat, and without this it would be re-seeded
    // (and re-diffed against) every single turn.
    setPocketsFor(charId, record);

    // The Journal remembers what changed hands (maintainer design,
    // 2026-08-11): deterministic diary cards from the ops just applied —
    // zero extra model calls. Gated on BOTH switches deliberately: pockets
    // produced the events, the Journal stores the memory; neither feature's
    // CORE rides the other (the independence rule), this is their
    // intersection. Guests never journal — the pass already runs only for
    // real cast members.
    if (events.isNotEmpty &&
        _storageService.memorySettings.journalEnabled &&
        _currentSessionId != null) {
      try {
        await _writeItemCards(charId, events, asContinuation: asContinuation);
      } catch (e) {
        // A diary miss must never cost the turn — same floor as the eval.
        debugPrint('[Journal] item cards skipped: $e');
      }
    }

    // Nothing moved for the bubble and no transfer to rewind — still
    // notify (record may have been first-seeded above) and stop.
    if (receipts.isEmpty && othersBefore.isEmpty) {
      notifyListeners();
      return;
    }

    // Receipts + rewind stamps ride the message the same way needs deltas
    // do (hostile review 2026-08-11 — pockets ops were the one non-scalar
    // turn effect nothing ever put back):
    //  * pockets_before rides SHARED metadata: pre-turn speaker kit (+
    //    `others` = each transfer recipient's pre-turn kit).
    //  * pockets_after rides THIS SWIPE: post-turn speaker kit (+
    //    `pockets_after_others` for recipients).
    //  * pocket_changes (the receipt chips) rides THIS SWIPE too — they
    //    describe the words in front of the reader, and each swipe moved its
    //    own things. It used to be written to the base map, which the bubble
    //    never reads once a swipe map exists (activeMetadata prefers
    //    swipeMetadata[i]) — so every user with Realism or Needs on, i.e.
    //    most of them, silently lost the chip (release audit 2026-08-15).
    final msg = _messages.isNotEmpty ? _messages.last : null;
    if (msg != null && !msg.isUser) {
      final existingBefore = msg.metadata?['pockets_before'];
      if (asContinuation &&
          existingBefore is Map &&
          existingBefore['char'] == charId) {
        // The first half already stamped the turn's true pre-state — keep
        // it. Only NEW transfer recipients union in (their pre-continuation
        // kit IS their pre-turn kit: the first half never touched them, or
        // they are already stamped and the first stamp wins).
        if (othersBefore.isNotEmpty) {
          final prior = (existingBefore['others'] as List?) ?? const [];
          final priorChars = <Object?>{
            for (final o in prior)
              if (o is Map) o['char'],
          };
          msg.metadata = {
            ...?msg.metadata,
            'pockets_before': {
              ...existingBefore,
              'others': [
                ...prior,
                for (final ob in othersBefore)
                  if (!priorChars.contains(ob['char'])) ob,
              ],
            },
          };
        }
      } else {
        // Normal turn — or a continuation whose first half applied no ops
        // and therefore never stamped: the record was still the turn's
        // pre-state when this pass captured beforeJson, so writing it now
        // is the same truth.
        final beforeStamp = <String, dynamic>{
          'char': charId,
          'record': beforeJson,
        };
        if (othersBefore.isNotEmpty) beforeStamp['others'] = othersBefore;
        msg.metadata = {...?msg.metadata, 'pockets_before': beforeStamp};
      }
      final afterMeta = <String, dynamic>{
        ...?msg.activeMetadata,
        'pockets_after': record.toJson(),
      };
      if (receipts.isNotEmpty) {
        // Continue appends to this swipe's own receipts (the first half's
        // chips describe the same swipe and must survive the extension).
        final prior = asContinuation
            ? (msg.activeMetadata?['pocket_changes'] as List?)
                  ?.whereType<String>()
            : null;
        afterMeta['pocket_changes'] = [...?prior, ...receipts];
      }
      // After-stamps carry each recipient's CURRENT kit: this pass's
      // recipients replace their old entry; first-half recipients this pass
      // did not touch keep theirs (their kit has not changed since).
      final priorAfterOthers = asContinuation
          ? (msg.activeMetadata?['pockets_after_others'] as List?)
          : null;
      if (othersAfter.isNotEmpty || (priorAfterOthers?.isNotEmpty ?? false)) {
        final newChars = <Object?>{for (final oa in othersAfter) oa['char']};
        afterMeta['pockets_after_others'] = [
          ...?priorAfterOthers?.where(
            (o) => o is Map && !newChars.contains(o['char']),
          ),
          ...othersAfter,
        ];
      }
      msg.activeMetadata = afterMeta;
      await _saveChat();
    }
    notifyListeners();
  }
}
