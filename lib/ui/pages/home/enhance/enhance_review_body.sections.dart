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

part of 'enhance_review_body.dart';

/// Per-field review cards (before/after, greetings, lorebook).
extension _EnhanceReviewBodySections on EnhanceReviewBodyState {
  Widget _sectionCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, String useKey) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
        ),
        Text(
          'Use this',
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        Switch(
          value: _use[useKey] ?? false,
          activeThumbColor: AppColors.porchAmberOf(context),
          onChanged: (v) => rebuildState(() => _use[useKey] = v),
        ),
      ],
    );
  }

  Widget _oldText(String label, String text) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary(context),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxHeight: 140),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Text(
              text.isEmpty ? '(empty)' : text,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _newField(
    String label,
    TextEditingController controller, {
    bool enabled = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.porchAmberOf(context),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          enabled: enabled,
          maxLines: null,
          minLines: 2,
          style: TextStyle(fontSize: 12, color: AppColors.textPrimary(context)),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surfaceContainerOf(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.borderOf(context)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: AppColors.porchAmberOf(context)),
            ),
            contentPadding: const EdgeInsets.all(8),
          ),
        ),
      ],
    );
  }

  Widget _fieldSection(String title, String key, String oldValue) {
    final use = _use[key] ?? false;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title, key),
          const SizedBox(height: 8),
          _oldText('Before', oldValue),
          const SizedBox(height: 8),
          _newField('After (editable)', _controllers[key]!, enabled: use),
        ],
      ),
    );
  }

  Widget _greetingsSection() {
    final use = _use['greetings'] ?? false;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader('First message + alternates', 'greetings'),
          const SizedBox(height: 8),
          _oldText('Before (first message)', widget.original.firstMessage),
          const SizedBox(height: 8),
          _newField(
            'After (editable)',
            _controllers['firstMessage']!,
            enabled: use,
          ),
          for (
            var i = 0;
            i < widget.enhanced.alternateGreetings.length;
            i++
          ) ...[
            const SizedBox(height: 8),
            _newField(
              'Alternate ${i + 1} (editable)',
              _controllers['alt$i']!,
              enabled: use,
            ),
          ],
        ],
      ),
    );
  }

  Widget _lorebookSection() {
    final entries = widget.enhanced.lorebook!.entries;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New lorebook entries',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < entries.length; i++)
            CheckboxListTile(
              value: _useLoreEntry[i],
              onChanged: (v) =>
                  rebuildState(() => _useLoreEntry[i] = v ?? false),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              activeColor: AppColors.porchAmberOf(context),
              checkColor: AppColors.onChaosAccent,
              contentPadding: EdgeInsets.zero,
              title: Text(
                entries[i].name,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary(context),
                ),
              ),
              subtitle: Text(
                entries[i].content,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
