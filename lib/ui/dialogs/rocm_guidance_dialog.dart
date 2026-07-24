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
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows a dialog with distro-specific ROCm installation instructions.
/// Returns true if the dialog was shown, false if suppressed by user preference.
Future<bool> showRocmGuidanceDialog(
  BuildContext context,
  String linuxDistro,
) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool('dismiss_rocm_guidance') == true) return false;

  if (!context.mounted) return false;

  final instructions = _getDistroInstructions(linuxDistro);

  await showDialog(
    context: context,
    builder: (context) =>
        _RocmGuidanceDialog(distro: linuxDistro, instructions: instructions),
  );
  return true;
}

class _RocmGuidanceDialog extends StatefulWidget {
  final String distro;
  final _RocmInstructions instructions;

  const _RocmGuidanceDialog({required this.distro, required this.instructions});

  @override
  State<_RocmGuidanceDialog> createState() => _RocmGuidanceDialogState();
}

class _RocmGuidanceDialogState extends State<_RocmGuidanceDialog> {
  bool _dontShowAgain = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E293B),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.speed, color: Colors.redAccent, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Boost AMD GPU Performance',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ROCm is AMD\'s GPU compute platform. Installing it enables native GPU acceleration, which is significantly faster than the Vulkan fallback.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Install instructions for ${widget.instructions.distroLabel}:',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              // Steps
              ...widget.instructions.steps.map(
                (step) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.instructions.steps.indexOf(step) + 1}. ',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          step,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Commands box
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: SelectableText(
                  widget.instructions.commands,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (widget.instructions.note != null)
                Text(
                  widget.instructions.note!,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
              const SizedBox(height: 12),
              const Text(
                'Consumer Radeon cards (RX 6000/7000/9000): ROCm\'s kernels '
                'target workstation chips, so these cards need the '
                'HSA_OVERRIDE_GFX_VERSION environment variable or KoboldCpp '
                'crashes at launch. Front Porch AI detects your card and '
                'sets this automatically when you enable ROCm — if you '
                'export your own value, yours wins.',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      color: Colors.blue,
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Currently using Vulkan as fallback. Restart the app after installing ROCm for automatic upgrade.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: Checkbox(
                      value: _dontShowAgain,
                      onChanged: (val) =>
                          setState(() => _dontShowAgain = val ?? false),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _dontShowAgain = !_dontShowAgain),
                    child: const Text(
                      'Don\'t show this again',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () {
            Clipboard.setData(
              ClipboardData(text: widget.instructions.commands),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Commands copied to clipboard!')),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copy Commands'),
        ),
        ElevatedButton(
          onPressed: () async {
            if (_dontShowAgain) {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('dismiss_rocm_guidance', true);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _RocmInstructions {
  final String distroLabel;
  final List<String> steps;
  final String commands;
  final String? note;

  _RocmInstructions({
    required this.distroLabel,
    required this.steps,
    required this.commands,
    this.note,
  });
}

_RocmInstructions _getDistroInstructions(String distro) {
  switch (distro) {
    case 'arch':
      return _RocmInstructions(
        distroLabel: 'Arch Linux / Manjaro',
        steps: [
          'Install the ROCm packages from the official repos:',
          'Reboot your system.',
          'Verify with: rocminfo',
        ],
        commands: 'sudo pacman -S rocm-hip-sdk rocm-opencl-sdk',
        note:
            'Manjaro/EndeavourOS users: packages are the same. AUR packages like rocm-hip-runtime may also work.',
      );
    case 'ubuntu':
      return _RocmInstructions(
        distroLabel: 'Ubuntu / Linux Mint / Pop!_OS',
        steps: [
          'Add the AMD ROCm apt repository:',
          'Install ROCm:',
          'Add your user to the render/video groups:',
          'Reboot your system.',
        ],
        commands:
            '# Add AMD GPG key and repo\n'
            'wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \\\n'
            '  gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null\n'
            'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] \\\n'
            '  https://repo.radeon.com/rocm/apt/latest jammy main" | \\\n'
            '  sudo tee /etc/apt/sources.list.d/rocm.list\n\n'
            '# Install\n'
            'sudo apt update\n'
            'sudo apt install rocm\n\n'
            '# Add user to GPU groups\n'
            'sudo usermod -aG render,video \$USER',
        note:
            'Replace "jammy" with your Ubuntu codename if needed (e.g. "noble" for 24.04). See: https://rocm.docs.amd.com',
      );
    case 'debian':
      return _RocmInstructions(
        distroLabel: 'Debian',
        steps: [
          'Add the AMD ROCm apt repository:',
          'Install ROCm:',
          'Add your user to the render/video groups:',
          'Reboot your system.',
        ],
        commands:
            '# Add AMD GPG key and repo\n'
            'wget https://repo.radeon.com/rocm/rocm.gpg.key -O - | \\\n'
            '  gpg --dearmor | sudo tee /etc/apt/keyrings/rocm.gpg > /dev/null\n'
            'echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/rocm.gpg] \\\n'
            '  https://repo.radeon.com/rocm/apt/latest bullseye main" | \\\n'
            '  sudo tee /etc/apt/sources.list.d/rocm.list\n\n'
            '# Install\n'
            'sudo apt update\n'
            'sudo apt install rocm\n\n'
            '# Add user to GPU groups\n'
            'sudo usermod -aG render,video \$USER',
        note:
            'Replace "bullseye" with your Debian version codename. See: https://rocm.docs.amd.com',
      );
    case 'fedora':
      return _RocmInstructions(
        distroLabel: 'Fedora',
        steps: [
          'Add the AMD ROCm repository:',
          'Install ROCm:',
          'Add your user to the render/video groups:',
          'Reboot your system.',
        ],
        commands:
            '# Add ROCm repo\n'
            'sudo tee /etc/yum.repos.d/rocm.repo <<EOF\n'
            '[ROCm]\n'
            'name=ROCm\n'
            'baseurl=https://repo.radeon.com/rocm/rhel9/latest/main\n'
            'enabled=1\n'
            'gpgcheck=1\n'
            'gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key\n'
            'EOF\n\n'
            '# Install\n'
            'sudo dnf install rocm\n\n'
            '# Add user to GPU groups\n'
            'sudo usermod -aG render,video \$USER',
        note:
            'For Fedora 39+ you may need to adjust the baseurl. See: https://rocm.docs.amd.com',
      );
    case 'rhel':
      return _RocmInstructions(
        distroLabel: 'RHEL / CentOS / Rocky / Alma',
        steps: [
          'Add the AMD ROCm repository:',
          'Install ROCm:',
          'Add your user to the render/video groups:',
          'Reboot your system.',
        ],
        commands:
            '# Add ROCm repo\n'
            'sudo tee /etc/yum.repos.d/rocm.repo <<EOF\n'
            '[ROCm]\n'
            'name=ROCm\n'
            'baseurl=https://repo.radeon.com/rocm/rhel9/latest/main\n'
            'enabled=1\n'
            'gpgcheck=1\n'
            'gpgkey=https://repo.radeon.com/rocm/rocm.gpg.key\n'
            'EOF\n\n'
            '# Install\n'
            'sudo dnf install rocm\n\n'
            '# Add user to GPU groups\n'
            'sudo usermod -aG render,video \$USER',
        note:
            'Use "rhel8" in the baseurl for RHEL 8.x. See: https://rocm.docs.amd.com',
      );
    case 'opensuse':
      return _RocmInstructions(
        distroLabel: 'openSUSE',
        steps: [
          'Add the AMD ROCm repository:',
          'Install ROCm:',
          'Add your user to the render/video groups:',
          'Reboot your system.',
        ],
        commands:
            '# Add ROCm repo\n'
            'sudo zypper addrepo \\\n'
            '  https://repo.radeon.com/rocm/zyp/latest/main rocm\n\n'
            '# Import GPG key\n'
            'sudo rpm --import https://repo.radeon.com/rocm/rocm.gpg.key\n\n'
            '# Install\n'
            'sudo zypper install rocm\n\n'
            '# Add user to GPU groups\n'
            'sudo usermod -aG render,video \$USER',
        note: 'See: https://rocm.docs.amd.com',
      );
    default:
      return _RocmInstructions(
        distroLabel: 'your Linux distribution',
        steps: [
          'Visit the official AMD ROCm installation guide:',
          'Follow the instructions for your specific distribution.',
          'After installing, reboot and verify with: rocminfo',
        ],
        commands:
            '# Visit: https://rocm.docs.amd.com/projects/install-on-linux/en/latest/',
        note:
            'Your distro was detected as "$distro". If this seems wrong, please file a bug report.',
      );
  }
}
