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

class LogView extends StatelessWidget {
  final List<String> logs;

  const LogView({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: ListView.builder(
        itemCount: logs.length,
        itemBuilder: (context, index) {
          // Reverse order to show newest at bottom if list is reversed, 
          // or just show normally. Assuming simpler list here.
          return SelectableText(
            logs[index],
            style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace', fontSize: 12),
          );
        },
      ),
    );
  }
}
