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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/settings/widgets/widgets.dart';
import 'package:front_porch_ai/ui/widgets/planner_feature_row.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'porch_life_defaults_note.dart';
import 'porch_life_engine_card.dart';

/// **Porch Life** — every "what makes characters feel alive" switch in one
/// place, grouped by what it is, each saying plainly what it needs.
///
/// Why this tab exists (docs/design/feature-independence.md, maintainer
/// 2026-08-07): these toggles used to live nested inside General's "Realism
/// Mode" card, which meant switching the Realism Engine OFF also HID the
/// switches for features that work fine without it — the welcome-back recap
/// and Story Weather among them. A three-agent code audit established which
/// features genuinely depend on the engine and which were merely filed under
/// it; the chips on each row report that finding rather than a guess.
///
/// Scope note: this tab holds the GLOBAL defaults; every one of them can still
/// be overruled by a single chat from its sidebar, which is what the closing
/// card now says.
///
/// Chaos Mode joined the tab on 2026-08-08 (maintainer: "Chaos mode should have
/// a global toggle in Porch life with no hard dep"). It was the last feature the
/// closing card had to apologise for — a paragraph explaining that one switch
/// lived somewhere else. `chaosModeDefault` OR-overrides the per-chat/per-group
/// seed at all three seed sites, the same shape Afterglow already used, so
/// leaving it off changes nothing for anyone.
///
/// Needs got its global switch here (`needsSimDefault`, 2026-08-07): it had
/// none at all, so the tab had nothing to show for the app's most visible
/// simulation. It AND-gates the card's own setting — default true, so nothing
/// changes until a user deliberately turns it off.
///
/// Dependency truths per the maintainer: Needs and Afterglow genuinely REQUIRE
/// the engine.
///
/// Passage of Time no longer does (2026-08-06). What the clock needs is a model
/// call sizing each exchange, not bond and trust — so it now runs on its own
/// eval when the engine is off, behind the opt-in sub-switch on that row. The
/// deterministic drift underneath remains what it always was: the cushion for
/// one failed call, never a mode and never offered as one. Weather and Dreams
/// follow the CLOCK rather than the engine, which is what this tab already
/// told users they did.
class PorchLifeTab extends StatelessWidget {
  const PorchLifeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final storage = context.watch<StorageService>();
    final chat = context.read<ChatService>();
    final realism = storage.realismSettings;

    // The engine gates everything in "needs Realism" rows; passage of time
    // additionally gates weather and dreams, and weather gates the °F display.
    final engineOn = storage.realismDefault;
    final timeOn = storage.passageOfTimeDefault;
    final weatherOn = storage.weatherEnabled;
    final journalOn = storage.journalEnabled;
    // Objectives depend on nothing but their own eval cost (maintainer,
    // 2026-08-07), and Ambitions hang off them: finishing a quest is the only
    // thing that moves ambition progress.
    final objectivesOn = storage.objectivesEnabled;
    final adultOn = storage.adultThemesEnabled;

    // Weather and dreams gate on the Passage of Time FLAG, deliberately not on
    // whether the clock is currently moving (ChatService._clockRunning). An
    // earlier draft used the latter, on the theory that it was more honest —
    // it is not, it is the old bug wearing a new hat. With the engine off and
    // the standalone opt-in off, gating on it greys out Story Weather again,
    // which is precisely the dead-switch problem this tab was built to end.
    // This tab sets DEFAULTS: a user must be able to record what they want now
    // and have it apply the moment the clock starts moving. The one fact that
    // subtlety depends on — "left off, the clock simply holds still" — is
    // stated on the row that owns it, one row above.

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Everything that makes a character feel like they live somewhere. '
          'Each switch says plainly what it needs — many need nothing at all.',
          style: TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 16),

        PorchLifeEngineCard(engineOn: engineOn, storage: storage, chat: chat),

        FeatureGroupCard(
          title: 'Time & World',
          subtitle: "the story's clock and sky",
          rows: [
            FeatureRow(
              icon: Icons.schedule,
              label: 'Passage of Time',
              need: FeatureNeed.alone,
              blurb:
                  'The story keeps its own clock — dawn to morning to evening '
                  'to night, day after day. The AI judges how long each '
                  'exchange actually took, so a shared meal moves the clock '
                  'further than a passing hello.',
              value: timeOn,
              onChanged: (v) {
                storage.setPassageOfTimeDefault(v);
                chat.setPassageOfTimeEnabled(v);
              },
              // Shown only with the engine off. With it on, the clock already
              // rides the engine's own reading of the scene and costs nothing
              // extra, so offering a switch there would be a choice about
              // nothing.
              child: engineOn
                  ? null
                  : StandaloneClockSwitch(
                      value: realism.standaloneClockEnabled,
                      onChanged: storage.setStandaloneClockEnabled,
                    ),
            ),
            FeatureRow(
              icon: Icons.cloud_outlined,
              label: 'Story Weather',
              need: FeatureNeed.needs,
              dependsOn: 'Passage of Time',
              satisfied: timeOn,
              blurb:
                  'Weather rolls through the story\'s days and is felt in mood '
                  'and comfort. Characters can see fronts coming ("looks like '
                  'rain tomorrow"). It costs no extra AI call — the sky is '
                  'worked out from the date — but it needs days to pass.',
              value: weatherOn,
              onChanged: storage.setWeatherEnabled,
            ),
            FeatureRow(
              icon: Icons.thermostat,
              label: 'Temperatures in °F',
              need: FeatureNeed.needs,
              dependsOn: 'Story Weather',
              satisfied: weatherOn,
              blurb:
                  'Display only — characters always experience weather in '
                  'words ("coat-and-gloves cold"), never numbers.',
              value: storage.weatherFahrenheit,
              onChanged: storage.setWeatherFahrenheit,
            ),
          ],
        ),

        FeatureGroupCard(
          title: 'Memory & Heart',
          subtitle: 'what they keep and carry',
          rows: [
            FeatureRow(
              icon: Icons.menu_book_outlined,
              label: 'The Journal',
              need: FeatureNeed.alone,
              blurb:
                  'Memory cards and the "where we are" recap, kept per chat and '
                  'never shared between chats. With the Realism Engine on, '
                  'cards also carry the feeling of the moment; without it they '
                  'are simply remembered.',
              value: journalOn,
              onChanged: storage.setJournalEnabled,
            ),
            FeatureRow(
              icon: Icons.nightlight_outlined,
              label: 'Dreams',
              need: FeatureNeed.needs,
              dependsOn: 'the Journal and Passage of Time',
              satisfied: journalOn && timeOn,
              blurb:
                  'When a story night passes, the character dreams — a short, '
                  'hazy scene woven from their memories, mood and the weather.',
              value: storage.dreamsEnabled,
              onChanged: storage.setDreamsEnabled,
            ),
            FeatureRow(
              icon: Icons.handshake_outlined,
              label: 'Promises',
              need: FeatureNeed.needs,
              dependsOn: 'the Journal',
              satisfied: journalOn,
              blurb:
                  'Commitments either of you make are remembered, and kept or '
                  'broken ones come back later. Uses one extra AI request per '
                  'reply to spot them, so it is slower and costs more on a paid '
                  'API. You can settle one yourself in the Journal\'s Promises '
                  'tab.',
              value: realism.promiseLedgerEnabled,
              onChanged: realism.setPromiseLedgerEnabled,
            ),
            FeatureRow(
              icon: Icons.checkroom_outlined,
              label: 'Pockets & Wardrobe',
              need: FeatureNeed.alone,
              blurb:
                  'What they are wearing and carrying is remembered instead of '
                  'scrolling out of the conversation — so the keys they picked '
                  'up an hour ago are still in their pocket, and the coat they '
                  'took off is still off. Items can change: a candy bar becomes '
                  'a wrapper, a sword gets notched. Uses one extra AI request '
                  'per reply to notice what changed, so it is slower and costs '
                  'more on a paid API. Kept per chat and cleared with it.',
              value: realism.pocketsEnabled,
              onChanged: realism.setPocketsEnabled,
            ),
            FeatureRow(
              icon: Icons.swap_horiz,
              label: 'Hand things between characters',
              need: FeatureNeed.needs,
              dependsOn: 'Pockets & Wardrobe',
              satisfied: realism.pocketsEnabled,
              blurb:
                  'In a group chat, when one character hands something to '
                  'another it actually moves — out of their pocket and into '
                  'the other\'s, keeping whatever condition it was in. Without '
                  'this, a handed-over item simply leaves the giver and reaches '
                  'no one. Costs nothing extra; it rides the check Pockets is '
                  'already doing. Best with a frontier model (Claude, GPT, '
                  'Gemini): it has to name WHO received the thing, which is '
                  'harder than noticing what changed, and smaller local models '
                  'often get the name wrong. When the name does not match '
                  'somebody in the chat, the app declines to guess — the item '
                  'leaves the giver and goes nowhere, exactly as before.',
              value: realism.pocketTransfersEnabled,
              onChanged: realism.setPocketTransfersEnabled,
            ),
            FeatureRow(
              icon: Icons.cloud_queue,
              label: 'Standing Mood',
              need: FeatureNeed.alone,
              blurb:
                  'Lets them arrive already in a mood you had nothing to do '
                  'with — tired, hungry, worn down by a week of rain, or '
                  'cheerful after a good night. Everything else in the app '
                  'reacts to YOU, which slowly makes you the centre of their '
                  'world; this is the part that is just their day. It is never '
                  'invented: it comes from what the app already tracks, and '
                  'hovering the mood chip tells you exactly what they walked '
                  'in carrying, so you can always tell their day from your '
                  'doing. Costs nothing — no extra AI request.',
              value: realism.standingMoodEnabled,
              onChanged: realism.setStandingMoodEnabled,
            ),
          ],
        ),

        FeatureGroupCard(
          title: 'Presence',
          subtitle: 'noticing you, nothing more',
          rows: [
            FeatureRow(
              icon: Icons.spa_outlined,
              label: 'Growth Rings',
              need: FeatureNeed.alone,
              blurb:
                  'Slow character evolution — rings, not rewrites. What they '
                  'live through is added as a new layer instead of overwriting '
                  'who they were.',
              value: storage.characterEvolutionEnabled,
              onChanged: storage.setCharacterEvolutionEnabled,
            ),
            FeatureRow(
              icon: Icons.track_changes,
              label: 'Objectives',
              need: FeatureNeed.alone,
              blurb:
                  'Short-lived quests a character works toward — set your own, '
                  'or let them decide what they want. Needs nothing else to '
                  'run, but it does check in with the AI to see whether a task '
                  'got done: every turn while the Realism Engine is on, and '
                  'every few messages while it is off. Switching this off is '
                  'the way to stop that cost — your quests are kept either way.',
              value: objectivesOn,
              onChanged: (v) {
                storage.setObjectivesEnabled(v);
                chat.setObjectivesEnabled(v);
              },
            ),
            FeatureRow(
              icon: Icons.flag_outlined,
              label: 'Ambitions',
              need: FeatureNeed.needs,
              dependsOn: 'Objectives',
              satisfied: objectivesOn,
              blurb:
                  'Long-term goals written on the character\'s card colour how '
                  'they steer a scene, and finishing an objective moves them a '
                  'little closer. Costs nothing extra — the goals are already '
                  'on the card — but finishing a quest is the only thing that '
                  'moves them, so they need Objectives running.',
              value: realism.ambitionsEnabled,
              onChanged: realism.setAmbitionsEnabled,
            ),
            PlannerFeatureRow(
              value: realism.plannerEnabled,
              timeOn: timeOn,
              objectivesOn: objectivesOn,
              journalOn: journalOn,
              onChanged: realism.setPlannerEnabled,
            ),
            FeatureRow(
              icon: Icons.person_search_outlined,
              label: 'Notice new characters',
              need: FeatureNeed.alone,
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
              icon: Icons.casino_outlined,
              label: 'Chaos Mode',
              need: FeatureNeed.alone,
              blurb:
                  'Pressure builds quietly as a scene goes on, and every so '
                  'often something happens that neither of you planned — a '
                  'knock at the door, a spilled drink, weather turning. The '
                  '2026-08-07 audit confirmed it runs perfectly well with the '
                  'Realism Engine off; it was only ever filed next to it. '
                  'Switching it on here turns it on for new chats and groups; '
                  'each chat can still overrule it in the sidebar.',
              value: realism.chaosModeDefault,
              onChanged: realism.setChaosModeDefault,
            ),
            FeatureRow(
              icon: Icons.history,
              label: 'Welcome-back recap',
              need: FeatureNeed.alone,
              blurb:
                  'After you have been away a while, opening a chat shows a '
                  'small "where we left off" banner. Uses the time of your last '
                  'message, already saved with your chat. Nothing new is '
                  'collected and nothing leaves your device.',
              value: storage.absenceBannerEnabled,
              onChanged: storage.setAbsenceBannerEnabled,
            ),
            FeatureRow(
              icon: Icons.waving_hand_outlined,
              label: 'Character notices your absence',
              need: FeatureNeed.alone,
              blurb:
                  'The character briefly acknowledges a long gap ("it\'s been a '
                  'few days") — once, in coarse words, never guessing what you '
                  'were doing. Same local-only timestamp as the recap banner.',
              value: storage.absenceAckEnabled,
              onChanged: storage.setAbsenceAckEnabled,
              child: AwayThreshold(storage: storage),
            ),
          ],
        ),

        // ── After Dark ──────────────────────────────────────────────────
        // The approved sketch gives the 18+ feature its own group, "shown only
        // when 18+ themes are enabled" — deliberately absent, not greyed out,
        // for anyone who has not asked for adult content. The master switch is
        // in Settings → General so it stays reachable while this is hidden.
        if (adultOn)
          FeatureGroupCard(
            title: 'After Dark',
            subtitle: 'shown only when 18+ themes are on',
            rows: [
              FeatureRow(
                icon: Icons.local_fire_department,
                label: 'Afterglow',
                need: FeatureNeed.needs,
                dependsOn: "Realism's arousal",
                satisfied: engineOn,
                blurb:
                    'Desire builds through a scene and settles afterwards '
                    'instead of resetting — so intimacy keeps a believable '
                    'rhythm and a character is not instantly ready to go '
                    'again. The engine is what scores desire, so this cannot '
                    'run without it — and nothing else, despite what it used '
                    'to do. Uses one short extra AI request per reply to '
                    'notice a climax, so it costs a little more on a paid API.',
                value: storage.nsfwCooldownDefault,
                onChanged: (v) {
                  storage.setNsfwCooldownDefault(v);
                  chat.setNsfwCooldownEnabled(v);
                },
              ),
              FeatureRow(
                icon: Icons.favorite,
                label: 'Acts on desires',
                need: FeatureNeed.needs,
                dependsOn: 'the Realism Engine',
                satisfied: engineOn,
                blurb:
                    'A character with intimate preferences on their card acts '
                    'on them instead of only reacting: they ask for what they '
                    'want, in their own voice — a dominant character presses '
                    'where a soft-spoken one hints — and turns down what they '
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
          ),

        const PorchLifeDefaultsNote(),
      ],
    );
  }
}
