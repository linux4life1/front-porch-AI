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

import 'chaos_event.dart';

const _spicy = <String>[
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
  '{{char}} has realized the only bed available tonight is very much a single',
  '{{char}} was handed a drink with an extremely suggestive name and now has to order another one out loud',
  'An explicit message just lit up {{char}}\'s screen while someone was looking over their shoulder',
  '{{char}} has been dared to kiss someone in the room and everyone is watching',
  '{{char}} spilled something and the only dry shirt on offer is far too small and far too sheer',
  'A massage, fitting, or adjustment {{char}} agreed to is getting much more intimate than expected, and they are not stopping it',
  '{{char}} lost a bet and now has to whisper something filthy to {{user}}',
  '{{char}} is wearing nothing under their coat and the coat is becoming a problem',
  'The walls are thin, the couple next door is very loud, and {{char}} cannot stop listening',
  '{{char}} found a toy that clearly belongs to someone they know and has to decide whether to mention it',
  '{{char}} has just been caught in a very compromising position by someone who is grinning about it',
  '{{char}} had an explicit dream about {{user}} last night and blushes every time {{user}} speaks',
  'The outfit {{char}} has to wear today is much more revealing than advertised',
  '{{char}} has been locked out of their room wearing only a towel',
  'Someone slipped {{char}} an invitation to a very private, very adult party tonight',
  '{{char}}\'s zipper, buttons, or laces have given up entirely at the worst moment',
  'A gust of wind has lifted {{char}}\'s clothing far higher than it should go, in full view',
  '{{char}} just realized they have been flirting back for ten minutes without meaning to',
  'A fortune teller, bartender, or stranger has just announced, loudly, exactly what {{char}} wants in bed',
  '{{char}}\'s private photos have just been glimpsed by the one person they least expected',
  'The only way through a tight space is pressed chest to chest, and {{char}} is stuck mid-squeeze',
  '{{char}} has been asked to model lingerie or swimwear for an eager crowd and somehow agreed',
  'An aphrodisiac was in the dessert, and {{char}} had seconds',
  '{{char}} has been mistaken for the evening\'s entertainment at a bachelor or bachelorette party',
  '{{char}} is stuck in a game of truth or dare and the next question is about their wildest night',
  '{{char}}\'s skinny-dip just got interrupted, and their clothes are on the other side of the crowd',
  'A very forward stranger has just offered {{char}} a night they will not forget, in front of {{user}}',
  '{{user}} has just caught {{char}} staring at them, and {{char}} did not look away in time',
  '{{char}} accidentally sent {{user}} a message that was very clearly meant to stay private',
  '{{char}} and {{user}} reached for the same thing and ended up far closer than either planned',
  'The hot tub, sauna, or bath {{char}} is in has just been joined by {{user}}',
  'The power went out and {{char}} is pressed close to {{user}} in the dark, and neither of them is moving away',
  '{{char}} walked in on {{other}} changing, and {{other}} did not ask them to leave',
  '{{other}} has just whispered something to {{char}} that left them bright red',
  '{{char}} and {{other}} have been caught in a closet together and nobody believes the explanation',
  'A game of spin the bottle has just landed {{char}} on {{other}}',
  '{{char}}\'s neck is covered in fresh marks and everyone has noticed',
  'An intimate item {{char}} ordered has been delivered to the wrong person, who is bringing it over',
  'The romance novel {{char}} was reading in secret has just been read aloud, at the steamiest part',
  '{{char}} is suddenly, intensely in the mood and it is very hard to hide',
];

const _needs = <String>[
  '{{char}} is in the middle of a very intimate moment when their bladder makes a very urgent demand',
  'The shower {{char}} is in has just run out of hot water mid-lather, and their towel is across the room in plain view',
  'The bathroom door swung open while {{char}} was using it, and someone got a full view',
  'A wardrobe malfunction in the bathroom has left {{char}} unable to get dressed again without help',
  '{{char}}\'s stomach growled loudly in the middle of a heated kiss',
  '{{char}} is so starving they are eating in a way that is accidentally very suggestive, and people are watching',
  'A long dry spell has caught up with {{char}} and they are restless, flustered, and thinking about little else',
  '{{char}} is so sleepy they just dozed off on {{user}} in a very compromising position',
  'The only bathroom has a glass door, and {{char}} really cannot wait any longer',
  '{{char}} spilled their drink down their front and is now soaked through and very see-through',
  '{{char}} is overheating and has taken off far more layers than the situation calls for',
  '{{char}} and {{other}} both rushed into the bathroom at once and the door just locked behind them',
];

/// Adult (18+) events. They reach the wheel only when the chat's spicy switch
/// AND the app-wide 18+ themes switch are both on. Every event is about
/// consenting adults; nothing here involves minors, coercion, or non-consent.
final List<ChaosEvent> kChaosAdultEvents = [
  for (final t in _spicy) ChaosEvent(ChaosCategory.spicy, t, adult: true),
  for (final t in _needs) ChaosEvent(ChaosCategory.needs, t, adult: true),
];
