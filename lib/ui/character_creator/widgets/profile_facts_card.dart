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

import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_input_label.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_text_card.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/profile_chip_list.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:front_porch_ai/ui/widgets/synced_text_field.dart';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "Also written from the interview" (docs/design/creator-ui-spec.md,
/// "Profile step"): every Front Porch fact the identity pass wrote, in the
/// spec's grid; edits go straight to the Realism values Save reads. It
/// dims to 45% while a rewrite or re-read runs.
class ProfileFactsCard extends StatelessWidget {
  const ProfileFactsCard({
    super.key,
    required this.state,
    required this.onReread,
  });

  final CreatorState state;
  final VoidCallback onReread;

  void _set(VoidCallback write) {
    write();
    state.notify();
    state.scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    final p = state.profile;
    final waiting = p.busy;
    final amber = StudioColors.amberOf(context);
    final age = state.ageController.text.trim();
    final reread = SizedBox(
      height: 36,
      child: OutlinedButton.icon(
        key: const ValueKey('profile-reread'),
        onPressed: waiting ? null : onReread,
        icon: const Icon(Icons.refresh, size: 16),
        label: const Text(
          'Re-read from the profile',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: amber,
          disabledForegroundColor: amber,
          side: BorderSide(color: amber, width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
    return Opacity(
      key: const ValueKey('profile-facts'),
      opacity: waiting ? 0.45 : 1,
      child: CreatorCardShell(
        title: 'Also written from the interview',
        subtitle: waiting
            ? 'Re-read after the rewrite'
            : 'Every Front Porch field is filled whether or not you use it. '
                  'Mood, time of day and outfit follow once the greeting '
                  'exists.',
        subtitleAmber: waiting,
        trailing: reread,
        children: [
          _row([
            _field(
              context,
              age.isEmpty ? 'BIRTHDAY' : 'BIRTHDAY · AGE $age FROM SETUP',
              state.realismBirthday,
              (v) => _set(() => state.realismBirthday = v),
            ),
            _field(
              context,
              'OCCUPATION',
              state.realismOccupation,
              (v) => _set(() => state.realismOccupation = v),
            ),
            _readOnly(context, 'HOURS · WORK DAYS', _hours()),
          ]),
          _row([
            _field(
              context,
              'OPENING TASK',
              state.realismCurrentTask,
              (v) => _set(() => state.realismCurrentTask = v),
            ),
            _readOnly(
              context,
              'OPENING STANCE TOWARD {{user}}',
              '${p.facts?.warmth ?? 'strangers'} · '
                  'bond ${state.realismShortTermBond} · '
                  'trust ${state.realismTrustLevel}',
            ),
          ]),
          _row([
            _chips(context, 'AMBITIONS', state.realismAmbitions, (v) {
              _set(() => state.realismAmbitions = v);
            }),
            _chips(context, 'WARMS TO', state.realismLikes, (v) {
              _set(() => state.realismLikes = v);
            }),
          ]),
          _row([
            _chips(context, 'PUT OFF BY', state.realismDislikes, (v) {
              _set(() => state.realismDislikes = v);
            }),
            if (state.nsfwEnabled) _intimate(context) else const SizedBox(),
          ]),
          _field(
            context,
            'CREATOR NOTES · THE PITCH',
            state.generatedCard?.creatorNotes ?? '',
            (v) => _set(() => state.generatedCard?.creatorNotes = v),
          ),
          if (p.factsError != null)
            Text(
              p.factsError!,
              key: const ValueKey('profile-facts-error'),
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: StudioColors.badOf(context),
              ),
            ),
        ],
      ),
    );
  }

  String _hours() {
    final days = state.realismWorkDays;
    final dayText = days == null || days.isEmpty
        ? 'Mon–Fri'
        : days.map((d) => _weekdays[(d - 1).clamp(0, 6)]).join(', ');
    final hours = state.realismHours;
    return hours.isEmpty ? 'No set hours' : '$hours · $dayText';
  }

  Widget _row(List<Widget> cells) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 20,
    children: [for (final c in cells) Expanded(child: c)],
  );

  Widget _labelled(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: 6,
    children: [CreatorInputLabel(label), child],
  );

  Widget _field(
    BuildContext context,
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) => _labelled(
    label,
    SyncedTextField(
      value: value,
      onChanged: onChanged,
      style: TextStyle(fontSize: 14, color: StudioColors.inkOf(context)),
      decoration: const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      ),
    ),
  );

  Widget _readOnly(BuildContext context, String label, String value) =>
      _labelled(
        label,
        Container(
          height: 40,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: StudioColors.bgOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: StudioColors.lineOf(context)),
          ),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              color: StudioColors.proseOf(context),
            ),
          ),
        ),
      );

  Widget _chips(
    BuildContext context,
    String label,
    List<String> values,
    ValueChanged<List<String>> onChanged,
  ) => _labelled(label, ProfileChipList(values: values, onChanged: onChanged));

  Widget _intimate(BuildContext context) {
    Widget sub(String text) => Text(
      text,
      style: TextStyle(fontSize: 12, color: StudioColors.mutedOf(context)),
    );
    return _labelled(
      'INTIMATE PREFERENCES · 18+ IS ON',
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          sub('into'),
          ProfileChipList(
            values: state.realismIntimateInto,
            onChanged: (v) => _set(() => state.realismIntimateInto = v),
          ),
          sub('not into'),
          ProfileChipList(
            values: state.realismIntimateNotInto,
            onChanged: (v) => _set(() => state.realismIntimateNotInto = v),
          ),
        ],
      ),
    );
  }
}
