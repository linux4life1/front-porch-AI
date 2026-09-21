// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Studio remote chips + searchable picker (Pro/paid labels, no ListTile ink
// assert on a 237-row list).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/backend_settings.dart';
import 'package:front_porch_ai/services/storage/settings/image_gen_settings.dart';
import 'package:front_porch_ai/services/storage/settings/remote_api_key_vault.dart';
import 'package:front_porch_ai/ui/image_studio/remote_image_host_chips.dart';
import 'package:front_porch_ai/ui/image_studio/settings_panel.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

void main() {
  testWidgets('Nano chip is enabled only when the vault has a key', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemoteImageHostChips(
            selectedUrl: kNanoGptApiV1,
            keyFor: (url) => url == kNanoGptApiV1 ? 'sk-nano' : '',
            onSelect: (url) => picked = url,
          ),
        ),
      ),
    );

    expect(find.text('Nano-GPT'), findsOneWidget);
    expect(find.text('OpenRouter'), findsOneWidget);
    expect(find.textContaining('Settings → Backend'), findsOneWidget);

    await tester.tap(find.byKey(const Key('image-remote-host-openrouter')));
    await tester.pump();
    expect(picked, isNull);

    await tester.tap(find.byKey(const Key('image-remote-host-nano')));
    await tester.pump();
    expect(picked, kNanoGptApiV1);
  });

  testWidgets(
    'search dialog lists Pro/paid, filters, and does not assert on ListTile ink',
    (tester) async {
      final models = [
        const ImageModelInfo(id: 'hidream', name: 'Hidream', isPaid: false),
        const ImageModelInfo(id: 'flux-2-pro', name: 'FLUX.2 Pro'),
        for (var i = 0; i < 80; i++)
          ImageModelInfo(id: 'paid-$i', name: 'Paid $i'),
      ];
      String? selected;
      final inkErrors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('ListTile background color or ink splashes')) {
          inkErrors.add(text);
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                backgroundColor: AppColors.background,
                body: DecoratedBox(
                  decoration: const BoxDecoration(color: AppColors.card),
                  child: TextButton(
                    onPressed: () =>
                        showGenericModelSearchDialog<ImageModelInfo>(
                          context,
                          [...models]..sort(compareImageModelsForPicker),
                          title: 'Select Image Model',
                          getTitle: imageModelListLabel,
                          getSubtitle: (m) => m.id,
                          onSelected: (m) => selected = m.id,
                        ),
                    child: const Text('open'),
                  ),
                ),
              );
            },
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Hidream · Pro'), findsOneWidget);
      expect(find.text('FLUX.2 Pro · paid'), findsOneWidget);
      expect(inkErrors, isEmpty);

      await tester.enterText(find.byType(TextField), 'hidream');
      await tester.pumpAndSettle();
      expect(find.text('Hidream · Pro'), findsOneWidget);
      expect(find.text('FLUX.2 Pro · paid'), findsNothing);

      await tester.tap(find.text('Hidream · Pro'));
      await tester.pumpAndSettle();
      expect(selected, 'hidream');
    },
  );

  testWidgets(
    'StudioSettingsPanel Material card does not hide ExpansionTile ink',
    (tester) async {
      final inkErrors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (text.contains('ListTile background color or ink splashes')) {
          inkErrors.add(text);
        }
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<StorageService>.value(
                value: _PanelStore(),
              ),
              ChangeNotifierProvider<ImageGenService>.value(
                value: _PanelImageGen(),
              ),
            ],
            child: const Scaffold(
              body: SingleChildScrollView(
                child: StudioSettingsPanel(initiallyExpanded: true),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Generation Settings'), findsOneWidget);
      expect(inkErrors, isEmpty);
    },
  );
}

class _PanelStore extends ChangeNotifier implements StorageService {
  @override
  final ImageGenSettings imageGenSettings = ImageGenSettings();
  @override
  final BackendSettings backendSettings = BackendSettings();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _PanelImageGen extends ChangeNotifier implements ImageGenService {
  @override
  Future<List<ImageModelInfo>> fetchImageModels() async => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
