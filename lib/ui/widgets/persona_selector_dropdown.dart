import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/user_persona_service.dart';
import '../theme/app_colors.dart';
import 'styled_dropdown.dart';

class PersonaSelectorDropdown extends StatelessWidget {
  const PersonaSelectorDropdown({
    super.key,
    required this.selectedPersonaId,
    required this.onChanged,
  });

  final String selectedPersonaId;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final personaService = Provider.of<UserPersonaService>(context);
    final personas = personaService.personas;

    return StyledDropdown<String>(
      value: selectedPersonaId,
      width: double.infinity,
      items: [
        DropdownMenuItem(
          value: '',
          child: Row(
            children: [
              Icon(
                Icons.person_off,
                size: 16,
                color: AppColors.textTertiary(context),
              ),
              const SizedBox(width: 8),
              Text(
                'None (Blank Slate)',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
            ],
          ),
        ),
        ...personas.map(
          (p) => DropdownMenuItem(
            value: p.id,
            child: Row(
              children: [
                Icon(
                  Icons.person,
                  size: 16,
                  color: Colors.blueAccent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    p.displayLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}
