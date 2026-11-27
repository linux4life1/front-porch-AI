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

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/existing_chats_offer_dialog.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Time & World group card: Passage of Time and its nested dependents
/// (Time-skip bridge, Scene suggestions, Story Weather -> Temperature Units).
class PorchLifeTimeGroup extends StatelessWidget {
  const PorchLifeTimeGroup({
    super.key,
    required this.storage,
    required this.expandDetailsSignal,
    required this.forceExpandVersion,
    required this.highlightedId,
    required this.rowKeyFor,
    required this.onJumpTo,
  });

  final StorageService storage;
  final ExpandSignal? expandDetailsSignal;
  final int forceExpandVersion;
  final String? highlightedId;
  final Key Function(String id) rowKeyFor;
  final ValueChanged<String> onJumpTo;

  @override
  Widget build(BuildContext context) {
    final realism = storage.realismSettings;
    final timeOn = realism.passageOfTimeDefault;
    final weatherOn = realism.weatherEnabled;

    return FeatureGroupCard(
      title: 'Time & World',
      subtitle: "the story's clock and sky",
      accentTint: AppColors.porchHoneyOf(context),
      forceExpandVersion: forceExpandVersion,
      rows: [
        FeatureTreeNode(
          active: timeOn,
          parent: FeatureRow(
            key: rowKeyFor('passage_of_time'),
            icon: Icons.schedule,
            label: 'Passage of Time',
            subtitle:
                "Runs the story's live clock across every open chat, pacing turns naturally.",
            need: FeatureNeed.alone,
            highlighted: highlightedId == 'passage_of_time',
            expandDetailsSignal: expandDetailsSignal,
            blurb:
                'The story keeps its own clock — dawn to morning to evening '
                'to night, day after day. This switch is what runs the clock '
                'in every open chat. Off pauses them immediately; on starts '
                'them again. The AI judges how long each exchange actually '
                'took, so a shared meal moves the clock further than a '
                'passing hello. A normal send always moves at least a '
                'minute or two.',
            value: timeOn,
            onChanged: realism.setPassageOfTimeDefault,
          ),
          children: [
            FeatureRow(
              icon: Icons.fast_forward_outlined,
              label: 'Time-skip bridge',
              subtitle:
                  'Fills in multi-day time skips with a short narrator bridge card.',
              need: FeatureNeed.needs,
              dependsOn: 'Passage of Time',
              satisfied: timeOn,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () => onJumpTo('passage_of_time'),
              blurb:
                  'When a message skips a day or more ("two weeks '
                  'later"), a short narrator card fills in how those days '
                  'went before the character replies. One short AI call, '
                  'only on a turn that skips that far. Off, the skip still '
                  'happens, just without the card.',
              value: realism.timeSkipBridgeEnabled,
              onChanged: realism.setTimeSkipBridgeEnabled,
            ),
            FeatureRow(
              icon: Icons.explore_outlined,
              label: 'Scene suggestions',
              subtitle:
                  'Offers to move the scene when a reply arrives at a named place.',
              need: FeatureNeed.needs,
              dependsOn: 'Passage of Time',
              satisfied: timeOn,
              expandDetailsSignal: expandDetailsSignal,
              onDependencyTap: () => onJumpTo('passage_of_time'),
              blurb:
                  'When the clock is running, the same turn read that moves '
                  'time also watches the story\'s PLACE. If a reply clearly '
                  'arrives somewhere in your world — up the stairs into the '
                  'Tea Rooms, out through the gate — the app offers to move '
                  'the scene there. You confirm or stay; it never moves the '
                  'scene by itself, and a plan or a passing mention is never '
                  'a move. Later updates add one more offer under this same '
                  'switch: saving a newly-named place the story walks into. '
                  'Off by default — offers in the middle of a scene are '
                  'welcome to some authors and noise to others.',
              value: realism.sceneSuggestionsEnabled,
              onChanged: realism.setSceneSuggestionsEnabled,
            ),
            FeatureTreeNode(
              active: timeOn && weatherOn,
              parent: FeatureRow(
                key: rowKeyFor('story_weather'),
                icon: Icons.cloud_outlined,
                label: 'Story Weather',
                subtitle:
                    'Date-driven weather fronts felt in character mood and comfort.',
                need: FeatureNeed.needs,
                dependsOn: 'Passage of Time',
                satisfied: timeOn,
                highlighted: highlightedId == 'story_weather',
                expandDetailsSignal: expandDetailsSignal,
                onDependencyTap: () => onJumpTo('passage_of_time'),
                blurb:
                    'Weather rolls through the story\'s days and is felt in mood '
                    'and comfort. Characters can see fronts coming ("looks like '
                    'rain tomorrow"). It costs no extra AI call — the sky is '
                    'worked out from the date — but it needs days to pass.',
                value: weatherOn,
                onChanged: realism.setWeatherEnabled,
              ),
              children: [
                FeatureRow(
                  icon: Icons.thermostat,
                  label: 'Temperature Units',
                  subtitle:
                      'Choose Celsius or Fahrenheit for sidebar weather displays.',
                  need: FeatureNeed.needs,
                  dependsOn: 'Story Weather',
                  satisfied: timeOn && weatherOn,
                  expandDetailsSignal: expandDetailsSignal,
                  blurb:
                      'Display only — characters always experience weather in '
                      'words ("coat-and-gloves cold"), never numbers.',
                  value: realism.weatherFahrenheit,
                  trailing: TemperatureUnitControl(
                    fahrenheit: realism.weatherFahrenheit,
                    onChanged: (timeOn && weatherOn)
                        ? realism.setWeatherFahrenheit
                        : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Presence group card: Chaos Mode, Notice new characters, Welcome-back recap,
/// and Character notices your absence.
class PorchLifePresenceGroup extends StatelessWidget {
  const PorchLifePresenceGroup({
    super.key,
    required this.storage,
    required this.expandDetailsSignal,
  });

  final StorageService storage;
  final ExpandSignal? expandDetailsSignal;

  @override
  Widget build(BuildContext context) {
    final realism = storage.realismSettings;

    return FeatureGroupCard(
      title: 'Presence',
      subtitle: 'noticing you, nothing more',
      accentTint: AppColors.porchTerracottaOf(context),
      rows: [
        FeatureRow(
          icon: Icons.casino_outlined,
          label: 'Chaos Mode',
          subtitle:
              'Builds quiet tension for occasional unplanned events in a scene.',
          need: FeatureNeed.alone,
          expandDetailsSignal: expandDetailsSignal,
          blurb:
              'Pressure builds quietly as a scene goes on, and every so '
              'often something happens that neither of you planned — a '
              'knock at the door, a spilled drink, weather turning. It '
              'works with or without the Realism Engine. Switching it on '
              'here turns it on for new chats and groups; each chat can '
              'still overrule it in the sidebar.',
          value: realism.chaosModeDefault,
          onChanged: realism.setChaosModeDefault,
          showChildWhenOff: true,
          child: ChaosFrequencyPicker(storage: storage),
        ),
        FeatureRow(
          icon: Icons.person_search_outlined,
          label: 'Notice new characters',
          subtitle:
              'Offers to bring newly named characters in the story into the cast.',
          need: FeatureNeed.alone,
          expandDetailsSignal: expandDetailsSignal,
          blurb:
              'Every few messages the app reads what was just narrated and, '
              'if a new named character has turned up in the story, offers '
              'to bring them in so they can speak for themselves. Switch '
              'this off and it stops asking — you can still invite someone '
              'in yourself at any time with the /scan command or the guest '
              'button. On by default; turn it off if the offers interrupt '
              'more than they help.',
          value: realism.sceneGuestDetectionEnabled,
          onChanged: realism.setSceneGuestDetectionEnabled,
        ),
        FeatureRow(
          icon: Icons.history,
          label: 'Welcome-back recap',
          subtitle:
              'Shows a brief "where we left off" banner after you have been away.',
          need: FeatureNeed.alone,
          expandDetailsSignal: expandDetailsSignal,
          blurb:
              'After you have been away a while, opening a chat shows a '
              'small "where we left off" banner. Uses the time of your last '
              'message, already saved with your chat. Nothing new is '
              'collected and nothing leaves your device.',
          value: realism.absenceBannerEnabled,
          onChanged: realism.setAbsenceBannerEnabled,
        ),
        FeatureRow(
          icon: Icons.waving_hand_outlined,
          label: 'Character notices your absence',
          subtitle:
              'Lets the character briefly acknowledge a long gap using local timestamps.',
          need: FeatureNeed.alone,
          expandDetailsSignal: expandDetailsSignal,
          blurb:
              'The character briefly acknowledges a long gap ("it\'s been a '
              'few days") — once, in coarse words, never guessing what you '
              'were doing. Same local-only timestamp as the recap banner.',
          value: realism.absenceAckEnabled,
          onChanged: realism.setAbsenceAckEnabled,
          child: AwayThreshold(storage: storage),
        ),
      ],
    );
  }
}

/// Conditional After Dark group card (shown only when 18+ themes are on).
class PorchLifeAfterDarkGroup extends StatelessWidget {
  const PorchLifeAfterDarkGroup({
    super.key,
    required this.storage,
    required this.engineOn,
    required this.expandDetailsSignal,
    required this.onJumpTo,
  });

  final StorageService storage;
  final bool engineOn;
  final ExpandSignal? expandDetailsSignal;
  final ValueChanged<String> onJumpTo;

  @override
  Widget build(BuildContext context) {
    final realism = storage.realismSettings;

    return FeatureGroupCard(
      title: 'After Dark',
      subtitle: 'shown only when 18+ themes are on',
      accentTint: AppColors.lustAccentOf(context),
      rows: [
        FeatureRow(
          icon: Icons.local_fire_department,
          label: 'Afterglow',
          subtitle:
              'Models lingering intimacy and cooldown rhythm instead of instant resets.',
          need: FeatureNeed.needs,
          dependsOn: "Realism's arousal",
          satisfied: engineOn,
          showDependencyBadge: true,
          expandDetailsSignal: expandDetailsSignal,
          onDependencyTap: () => onJumpTo('realism'),
          blurb:
              'Desire builds through a scene and settles afterwards '
              'instead of resetting — so intimacy keeps a believable '
              'rhythm and a character is not instantly ready to go '
              'again. The engine is what scores desire, so this cannot '
              'run without it. Uses one short extra AI request per reply '
              'to notice a climax, so it costs a little more on a paid '
              'API. Multiorgasmic characters feel a tenderness window '
              'instead of a lock. Off: no chat tracks Lust, and the '
              'Afterglow switches on characters and chats are hidden. '
              'Each chat keeps its own choice for when you turn this '
              'back on.',
          value: realism.nsfwCooldownDefault,
          onChanged: (v) async {
            final was = realism.afterglowEnabled;
            await realism.setNsfwCooldownDefault(v);
            if (!context.mounted) return;
            await offerAfterglowInExistingChats(context, wasAllowed: was);
          },
        ),
        FeatureRow(
          key: const ValueKey('classic-lust-row'),
          icon: Icons.history,
          label: 'Classic Lust bar',
          subtitle:
              'Off shows the Heat bar under Lust. On keeps the old single Lust bar.',
          need: FeatureNeed.needs,
          dependsOn: 'Afterglow',
          satisfied: engineOn && realism.afterglowEnabled,
          showDependencyBadge: true,
          expandDetailsSignal: expandDetailsSignal,
          onDependencyTap: () => onJumpTo('realism'),
          blurb:
              'Off (the default): Lust is how much a character wants it, '
              'and a separate Heat bar shows how close they are to '
              'release. Heat only builds during intimate contact, so a '
              'long flirt does not end on the first touch. On: the way it '
              'worked before Heat — one Lust bar decides both, and no '
              'Heat bar shows. Turning it on keeps each chat\'s Heat, so '
              'turning it off again picks up where it was. Costs nothing '
              'either way.',
          value: realism.classicLustEnabled,
          onChanged: realism.setClassicLustEnabled,
        ),
        FeatureRow(
          icon: Icons.favorite,
          label: 'Acts on desires',
          subtitle:
              'Lets characters proactively voice and pursue intimate card preferences.',
          need: FeatureNeed.needs,
          dependsOn: 'the Realism Engine',
          satisfied: engineOn,
          showDependencyBadge: true,
          expandDetailsSignal: expandDetailsSignal,
          onDependencyTap: () => onJumpTo('realism'),
          blurb:
              'A character with intimate preferences on their card acts '
              'on them instead of only reacting: they ask for what they '
              'want, in their own voice — a dominant character presses '
              'where a soft-spoken one hints — and turn down what they '
              'are not interested in rather than going along with it. '
              'Being refused something they wanted shows in their mood '
              'afterwards, sharper or quieter as fits who they are. Needs '
              'the engine because that is what scores the answer they '
              'get; without it they would ask and nothing would ever '
              'come of it. Costs nothing extra — no AI request, just '
              'two more lines in the prompt.',
          value: realism.intimateAgencyEnabled,
          onChanged: realism.setIntimateAgencyEnabled,
        ),
      ],
    );
  }
}
