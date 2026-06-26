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
import 'package:front_porch_ai/services/web/web_server_host.dart';

/// Full-screen overlay that blocks the Flutter desktop UI when a remote
/// web client is connected via the HTTP server.
///
/// Shows connection info and a "Disconnect" button so the user can
/// reclaim control of the local app.
class RemoteLockOverlay extends StatelessWidget {
  const RemoteLockOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<WebServerHost>(
      builder: (context, webServer, _) {
        if (!webServer.hasActiveClient) {
          return const SizedBox.shrink();
        }

        return Positioned.fill(
          child: Material(
            color: const Color(0xFF0F172A),
            child: Center(
              child: SizedBox(
                width: 480,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pulsing connection icon
                    _PulsingIcon(),
                    const SizedBox(height: 32),

                    // Title
                    const Text(
                      'Remote Client Connected',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Subtitle
                    Text(
                      'The local interface is locked while a device is\nconnected via the web server.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Connection info card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          _InfoRow(
                            icon: Icons.devices,
                            label: 'Connected Device',
                            value: webServer.connectedClientInfo ?? 'Unknown',
                          ),
                          const SizedBox(height: 12),
                          _InfoRow(
                            icon: Icons.language,
                            label: 'Server Address',
                            value:
                                'http://${webServer.lanIp ?? "..."}:${webServer.port}',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Disconnect button
                    SizedBox(
                      width: 240,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: () => webServer.disconnectClient(),
                        icon: const Icon(Icons.link_off, size: 20),
                        label: const Text(
                          'Disconnect',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.shade700,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.blueAccent, size: 18),
        const SizedBox(width: 10),
        Text(
          '$label:',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

/// Animated pulsing WiFi icon.
class _PulsingIcon extends StatefulWidget {
  @override
  State<_PulsingIcon> createState() => _PulsingIconState();
}

class _PulsingIconState extends State<_PulsingIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _animation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blueAccent.shade700, Colors.cyanAccent.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.blueAccent.withValues(
                  alpha: 0.3 * _animation.value,
                ),
                blurRadius: 24 * _animation.value,
                spreadRadius: 4 * _animation.value,
              ),
            ],
          ),
          child: const Icon(
            Icons.wifi_tethering,
            size: 40,
            color: Colors.white,
          ),
        );
      },
    );
  }
}
