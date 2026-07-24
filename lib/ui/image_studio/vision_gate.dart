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

import 'package:front_porch_ai/services/capability/model_capabilities.dart';
import 'package:front_porch_ai/services/capability/vision_support_resolver.dart';
import 'package:front_porch_ai/services/expression_pack_qc.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/vision_eval.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// The ONE click-time vision gate for every Vision-QC surface (the Studio's
/// pack grid, the creator's Portrait & Avatars panel): resolve whether the
/// active text LLM can see images and hand back the vision-eval closure — or
/// explain why not with the shared warm dialog and return null.
///
/// Only ever call this from an explicit user action: for generic
/// OpenAI-compatible remotes the resolver's first verdict costs a tiny probe
/// request, so it must never run automatically on dialog/step open (probes
/// also mis-verdict while a local server is still loading its model).
Future<VisionEvalFn?> resolveVisionFireWithExplainer(
  BuildContext context,
) async {
  final llmProvider = Provider.of<LLMProvider>(context, listen: false);
  final storage = Provider.of<StorageService>(context, listen: false);
  final support = await VisionSupportResolver.instance.resolveForActiveLlm(
    backend: llmProvider.activeBackend,
    storage: storage,
  );
  if (!context.mounted) return null;
  if (!support.supported) {
    final unknown = support.source == VisionSource.unknown;
    await showWarmDialog(
      context,
      title: unknown ? 'Couldn\'t check vision' : 'No vision model',
      icon: Icons.visibility_off_outlined,
      accent: AppColors.formMasterAccent,
      content: WarmDialogText(
        unknown
            ? 'The model server didn\'t answer the vision check (it may '
                  'still be loading the model). Make sure it\'s running '
                  'with your model loaded, then try again.'
            : 'Your current text model can\'t see images. Local models '
                  'need a vision-capable GGUF with its mmproj loaded '
                  '(Model Settings → Vision); for remote APIs pick a '
                  'vision-capable model.',
      ),
      actions: [warmDialogCancel(context, label: 'Got it')],
    );
    return null;
  }
  final llm = llmProvider.activeService;
  return ({required String prompt, required List<String> imagesB64}) =>
      fireVisionEval(llm: llm, prompt: prompt, imagesB64: imagesB64);
}
