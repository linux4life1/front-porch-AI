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

const _social = <String>[
  '{{char}} has just been asked to settle a very personal argument between two strangers',
  'Someone from {{char}}\'s past has recognized them and is coming over, beaming',
  '{{char}} has been roped into a group photo, toast, or ceremony with people they do not know',
  'A rumor about {{char}} is spreading nearby and it is wildly inaccurate',
  '{{char}} is being very obviously flirted with by someone they have no interest in',
  '{{char}} just received news that changes their plans for the rest of the day',
  'A very nosy person has decided {{char}} is their new best friend and will not leave',
  '{{char}} has been mistaken for a guide, clerk, or staff member and someone needs help right now',
  'A child has just asked {{char}} a deeply uncomfortable question in front of everyone',
  '{{char}} has been volunteered for something by someone else, loudly and without asking',
  'A rival of {{char}}\'s has just walked in and spotted them immediately',
  '{{char}} overhears a stranger badmouthing something {{char}} loves',
  'An old friend of {{char}}\'s needs a favor, urgently, and will not take no for an answer',
  '{{char}} has just been publicly thanked for something they did not actually do',
  'Someone nearby is crying and {{char}} is the only one who noticed',
  '{{user}} has just been mistaken for {{char}}\'s partner by a very insistent stranger',
  'A stranger has just told {{user}} an embarrassing story about {{char}} that {{char}} did not know anyone knew',
  '{{char}} and {{other}} have both been mistaken for a couple and nobody will believe otherwise',
  '{{char}} has just found out {{other}} has been keeping a small secret from them',
  '{{other}} just told everyone a story about {{char}} that {{char}} remembers very differently',
  '{{char}} and {{other}} have been asked to judge a contest together and completely disagree',
];

const _weather = <String>[
  'A sudden downpour has started and the only shelter nearby is very small',
  'The lights, lamps, or fire have gone out without any warning',
  'A thick fog has rolled in and nobody can see more than a few feet',
  'It is suddenly, unreasonably hot and everyone nearby is suffering',
  'A bitter cold snap has hit and {{char}} is dressed for the wrong season',
  'A distant bell, alarm, or horn has started ringing and will not stop',
  'The ground just trembled, briefly, and everyone froze',
  'A strong wind has picked up and is stealing hats, papers, and anything not held down',
  'Thunder cracked directly overhead loud enough to make {{char}} jump',
  'A rainbow, aurora, or strange light has appeared in the sky and everyone has stopped to stare',
  'The way ahead is suddenly blocked: a flood, a fallen tree, a collapsed path, or a locked gate',
  'Snow, hail, or ash has started falling out of nowhere',
  'A smell of smoke is drifting in from somewhere nearby',
  'Everything around {{char}} has gone completely silent, as if the world is holding its breath',
  'A swarm of insects has descended on the area and they love {{char}} in particular',
  'A sudden gust has blown a door, window, or tent flap wide open',
  '{{char}} and {{other}} are stuck sheltering together in a very cramped space until the weather passes',
];

const _plotHook = <String>[
  '{{char}} notices someone has been following them for a while',
  'A stranger pressed a note into {{char}}\'s hand and vanished into the crowd',
  '{{char}} has found a key, map, or token that clearly belongs to something important',
  'Someone nearby collapsed and {{char}} is the closest person to help',
  '{{char}} overhears their own name in a conversation they were not meant to hear',
  'An official-looking person is asking around about {{char}}',
  'A message meant for someone else has reached {{char}} by mistake, and it is alarming',
  '{{char}} has just spotted something that should not be here, here',
  'Someone is offering {{char}} a deal that sounds far too good to be true',
  '{{char}} realizes something of theirs has been stolen, and the thief is still in sight',
  'A frightened stranger has begged {{char}} to hide them, right now',
  '{{char}} has just found a hidden door, compartment, or passage',
  'A familiar face {{char}} thought was gone for good has just walked past',
  'Someone has left a wrapped package with {{char}}\'s name on it, and no sender',
  '{{char}} witnesses something they were clearly not supposed to see, and someone saw them see it',
  'A loud commotion has broken out nearby and people are running toward it',
  '{{char}} has been handed something to hold "for just a minute" and the owner has not come back',
  'An animal is trying very hard to lead {{char}} somewhere',
  '{{user}} has just been handed a sealed letter addressed to {{char}}',
  'Someone has been asking questions about {{user}}, and {{char}} heard about it first',
  '{{char}} just caught {{other}} somewhere they said they would not be',
];

const _needs = <String>[
  '{{char}} is suddenly, ravenously hungry and their stomach is announcing it to the room',
  '{{char}} has an overwhelming craving and will not be able to think about anything else until it is handled',
  '{{char}} is desperately thirsty and there is nothing to drink anywhere in sight',
  '{{char}} needs a bathroom immediately and the only one nearby is out of order',
  'The toilet {{char}} just used will not stop running, overflowing, or making noise',
  'The bathroom lock {{char}} is behind has jammed, and someone is knocking',
  'There is no toilet paper and {{char}} has discovered this far too late',
  '{{char}} has been holding it for far too long and is now walking very carefully',
  'The bathroom {{char}} chose has a door that does not close all the way',
  '{{char}}\'s last meal is disagreeing with them, loudly and urgently',
  '{{char}} is hit by a wave of exhaustion so heavy they could fall asleep standing up',
  '{{char}} just realized they have not showered in a while, and someone else noticed first',
  '{{char}} has a pounding headache that arrived out of nowhere',
  '{{char}} has a cramp in their leg at the worst possible moment',
  '{{char}}\'s blood sugar has crashed and they are getting shaky and short-tempered',
  '{{char}} ate something far spicier than expected and is fighting for their life',
  '{{char}} cannot stop yawning and it is spreading to everyone around them',
  '{{char}} is cold to the bone and cannot stop shivering',
  '{{char}} has been sitting so long their foot has gone completely numb, and now they have to stand',
  'The smell of food cooking nearby is making {{char}} lose all focus',
  '{{char}} is desperately lonely all of a sudden and wants company, badly',
  '{{char}} is bored out of their mind and about to do something reckless about it',
  '{{char}}\'s clothes are suddenly unbearably uncomfortable: too tight, itchy, or damp',
  'A hiccup, burp, or gurgle has escaped {{char}} at full volume',
  '{{user}}\'s stomach just growled loudly and {{char}} heard every second of it',
  '{{char}} and {{other}} both need the only bathroom at the same moment',
  '{{other}} has eaten the snack {{char}} was saving, and {{char}} is starving',
];

/// Newer SFW kinds: social mix-ups, weather and surroundings, plot hooks, and
/// the body's needs (hunger, thirst, the bathroom, sleep). Also the first
/// events aimed at the user or at a pair of group members.
final List<ChaosEvent> kChaosExpandedEvents = [
  for (final t in _social) ChaosEvent(ChaosCategory.social, t),
  for (final t in _weather) ChaosEvent(ChaosCategory.weather, t),
  for (final t in _plotHook) ChaosEvent(ChaosCategory.plotHook, t),
  for (final t in _needs) ChaosEvent(ChaosCategory.needs, t),
];
