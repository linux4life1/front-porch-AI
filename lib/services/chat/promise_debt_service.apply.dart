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

part of 'promise_debt_service.dart';

/// Plant / resolve apply path for [PromiseDebtService].
extension PromiseDebtApply on PromiseDebtService {
  Future<void> _plantOpen({
    required String sessionId,
    required String characterId,
    required String characterName,
    required String userName,
    required String party,
    required String text,
    int? receiptPosition,
    int? storyDay,
    String? storyClock,
  }) async {
    final content = party == 'user'
        ? '$userName gave their word: $text'
        : 'I promised $userName: $text';
    await journalStore.addCard(
      sessionId: sessionId,
      characterId: characterId,
      content: content,
      category: 'moment',
      kind: 'promise',
      emotionLabel: party == 'user' ? 'hopeful' : 'determined',
      emotionIntensity: 'moderate',
      sourcePositions: receiptPosition == null
          ? const <int>[]
          : <int>[receiptPosition],
      storyDay: storyDay,
      storyClock: storyClock,
      maxCards: getMaxCards(),
    );
    // Stamp party + status + short description (addCard only writes kind/story).
    for (final card in await journalStore.cardsFor(sessionId, characterId)) {
      final meta = PromiseDebtService.metaOf(card.metadata);
      if (meta['kind'] == 'promise' && meta['status'] == null) {
        await journalStore.updateCardMetadata(card, {
          'party': party,
          'status': 'open',
          'description': text,
        });
        break;
      }
    }
    await listOpen(sessionId, characterId); // refresh cache
    _markLedgerActivity(sessionId, characterId);
    onCacheWarmed?.call();
    debugPrint('[PromiseDebt] NEW $party: $text');
  }

  Future<void> _resolve({
    required String sessionId,
    required String characterId,
    required OpenPromise item,
    required bool kept,
    int? storyDay,
    String? storyClock,
    int? receiptPosition,
  }) async {
    JournalMemoryData? card;
    for (final c in await journalStore.cardsFor(sessionId, characterId)) {
      if (c.id == item.cardId) {
        card = c;
        break;
      }
    }
    if (card == null) return;

    final status = kept ? 'kept' : 'broken';
    final past = kept
        ? (item.party == 'user'
              ? 'They kept their word: ${item.text}'
              : 'I kept my word: ${item.text}')
        : (item.party == 'user'
              ? 'They broke their word: ${item.text}'
              : 'I broke my word: ${item.text}');

    await journalStore.reviseCard(card, content: past);
    // re-fetch after revise (heat re-warmed; id stable)
    for (final c in await journalStore.cardsFor(sessionId, characterId)) {
      if (c.id == item.cardId) {
        card = c;
        break;
      }
    }
    await journalStore.updateCardMetadata(card!, {
      'status': status,
      'party': item.party,
      'kind': 'promise',
    });

    // Outcome milestone for Our Story (timeline-salient, never cools).
    await journalStore.addCard(
      sessionId: sessionId,
      characterId: characterId,
      content: past,
      category: 'moment',
      kind: 'milestone',
      emotionLabel: kept
          ? (item.party == 'user' ? 'relieved' : 'proud')
          : (item.party == 'user' ? 'hurt' : 'ashamed'),
      emotionIntensity: kept ? 'moderate' : 'strong',
      sourcePositions: receiptPosition == null
          ? const <int>[]
          : <int>[receiptPosition],
      storyDay: storyDay,
      storyClock: storyClock,
      maxCards: getMaxCards(),
    );

    // Simulation pressure — user party only moves trust.
    if (item.party == 'user') {
      if (kept) {
        applyTrustDelta(PromiseDebtService.kKeptUserTrust);
        applyBondDelta(PromiseDebtService.kKeptUserBond);
      } else {
        applyTrustDelta(PromiseDebtService.kBrokenUserTrust);
        applyBondDelta(PromiseDebtService.kBrokenUserBond);
      }
    } else {
      applyBondDelta(
        kept
            ? PromiseDebtService.kKeptCharBond
            : PromiseDebtService.kBrokenCharBond,
      );
    }

    await listOpen(sessionId, characterId);
    _markLedgerActivity(sessionId, characterId);
    onSalienceKick?.call();
    onCacheWarmed?.call();
    debugPrint('[PromiseDebt] $status (${item.party}): ${item.text}');
  }
}
