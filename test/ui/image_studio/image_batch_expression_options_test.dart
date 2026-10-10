// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/image.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt.dart';
import 'expression_workspace_test.dart' as fixture;

void main() {
  testWidgets('full batch skips existing expressions and freezes local rules', (
    tester,
  ) async {
    final rig = await fixture.workspaceRig(tester);
    late ImageBatchService queue;
    var done = false;
    Object? failure;
    await tester.runAsync(() async {
      () async {
            rig.storage.expressionSettings.initializeBase(
              rig.storage.imageGenSettings.prefs!,
              rig.storage.notifyListeners,
            );
            queue = ImageBatchService(rig.storage, rig.image);
            await queue.ready;
            await rig.repository.addAvatar(
              rig.first.dbId!,
              rig.first.name,
              rig.image.picture,
              kFullExpressionSet.first,
            );
            await rig.storage.expressionSettings.setExpressionPromptRules(
              ExpressionPromptRules(prefix: 'global'),
            );
            await queue.prepare(
              repository: rig.repository,
              characterIds: [rig.first.dbId!],
              kind: 'expressions',
              prompt: '{character} in a garden',
              fullSet: true,
              promptRules: ExpressionPromptRules(
                prefix: 'local',
                suffix: 'keep the costume',
              ),
            );
            await rig.storage.expressionSettings.setExpressionPromptRules(
              ExpressionPromptRules(prefix: 'changed'),
            );
          }()
          .then<void>((_) {
            done = true;
          })
          .catchError((Object e) {
            failure = e;
            done = true;
          });
    });
    for (var i = 0; i < 100 && !done; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(done, isTrue);
    if (failure != null) throw failure!;
    expect(
      queue.jobs.map((j) => j.label).toSet(),
      kFullExpressionSet.skip(1).toSet(),
    );
    expect(queue.jobs, hasLength(kFullExpressionSet.length - 1));
    for (final job in queue.jobs) {
      expect(job.prompt, startsWith('local '));
      expect(job.prompt, endsWith('keep the costume'));
      expect(job.prompt, contains('First card in a garden'));
    }
  });
}
