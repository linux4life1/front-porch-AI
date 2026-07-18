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

import 'dart:io';

/// Returns this host's first private IPv4 LAN address (192.168.x, 10.x, or
/// 172.16–31.x), or null if none is found. Used to advertise the reachable LAN
/// URL when the web server binds all interfaces. Extracted from WebServerHost
/// so the host stays under the file-size cap and this stays independently
/// testable.
Future<String?> detectPrivateLanIp() async {
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final ip = addr.address;
        if (ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            _is172Private(ip)) {
          return ip;
        }
      }
    }
  } catch (_) {}
  return null;
}

bool _is172Private(String ip) {
  if (!ip.startsWith('172.')) return false;
  final second = int.tryParse(ip.split('.')[1]) ?? 0;
  return second >= 16 && second <= 31;
}
