import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/utils/picker_prefs.dart';

class ExportPersonaDialog extends StatefulWidget {
  final List<UserPersona> personas;

  const ExportPersonaDialog({super.key, required this.personas});

  @override
  State<ExportPersonaDialog> createState() => _ExportPersonaDialogState();
}

class _ExportPersonaDialogState extends State<ExportPersonaDialog> {
  bool _exportAll = true;
  String? _selectedPersonaId;

  @override
  void initState() {
    super.initState();
    if (widget.personas.isNotEmpty) {
      _selectedPersonaId = widget.personas.first.id;
    }
  }

  void _export() async {
    final service = Provider.of<UserPersonaService>(context, listen: false);

    String defaultName = _exportAll
        ? 'FPAI_personas.json'
        : '${widget.personas.firstWhere((p) => p.id == _selectedPersonaId).name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_')}_FPAIpersona.json';

    String? outputFile = await PickerPrefs.saveFile(
      category: PickerPrefs.catExport,
      dialogTitle: 'Export Personas',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.json')) outputFile += '.json';

      List<String> idsToExport = _exportAll
          ? widget.personas.map((p) => p.id).toList()
          : [_selectedPersonaId!];

      await service.exportPersonasToSTFormat(idsToExport, outputFile);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Exported to $outputFile',
              style: TextStyle(color: AppColors.textPrimary(context)),
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.personas.isEmpty) {
      return AlertDialog(
        backgroundColor: AppColors.surfaceContainerOf(context),
        title: const Text('Export Personas'),
        content: const Text('No personas to export.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppColors.surfaceContainerOf(context),
      title: const Text('Export Personas'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Export Mode',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          DropdownButton<bool>(
            isExpanded: true,
            value: _exportAll,
            dropdownColor: AppColors.surfaceContainerOf(context),
            items: [
              DropdownMenuItem<bool>(
                value: true,
                child: Text(
                  'Export All Personas',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
              ),
              DropdownMenuItem<bool>(
                value: false,
                child: Text(
                  'Export Singular Persona',
                  style: TextStyle(color: AppColors.textPrimary(context)),
                ),
              ),
            ],
            onChanged: (val) {
              setState(() {
                _exportAll = val!;
              });
            },
          ),
          if (!_exportAll) ...[
            const SizedBox(height: 16),
            Text(
              'Select Persona',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButton<String>(
              isExpanded: true,
              value: _selectedPersonaId,
              dropdownColor: AppColors.surfaceContainerOf(context),
              items: widget.personas.map((p) {
                return DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(
                    p.displayLabel,
                    style: TextStyle(color: AppColors.textPrimary(context)),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                setState(() {
                  _selectedPersonaId = val;
                });
              },
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(context)),
          ),
        ),
        ElevatedButton(
          onPressed: _export,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            foregroundColor: Colors.white,
          ),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
