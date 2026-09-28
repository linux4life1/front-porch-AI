import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/draw_things_samplers.dart';
import 'package:front_porch_ai/services/image/studio_recipe.dart';
import 'package:front_porch_ai/services/image/studio_recipe_migrate.dart';

void main() {
  test('z-image keeps its diffusion file and ignores a leftover Qwen name', () {
    final prefs = <String, Object?>{
      'image_gen_backend': 'comfyui',
      'comfy_create_workflow_id': 'z_image_turbo',
      'image_gen_model': 'qwen_image_bf16.safetensors',
      'comfy_create_model_choices':
          '{"z_image_turbo/%MODEL_DIFFUSION%":"z_image_turbo_bf16.safetensors",'
          '"flux/%MODEL_DIFFUSION%":"flux1-dev.safetensors",'
          '"z_image_turbo/%MODEL_CLIP%":"qwen_3_4b.safetensors"}',
      'comfy_create_uploaded_workflow': '{"1":{"class_type":"KSampler"}}',
      'image_gen_size': '1024x1536',
    };
    final before = Map<String, Object?>.from(prefs);
    final recipe = migrateImageStudioRecipe(prefs);
    expect(prefs, before);
    expect(recipe.create.workflowId, 'z_image_turbo');
    expect(recipe.create.customWorkflow, isFalse);
    expect(recipe.create.uploadedJson, isEmpty);
    expect(recipe.create.primaryFile, 'z_image_turbo_bf16.safetensors');
    expect(recipe.create.support['%MODEL_CLIP%'], 'qwen_3_4b.safetensors');
    expect(
      recipe.create.support.containsKey('flux/%MODEL_DIFFUSION%'),
      isFalse,
    );
    expect(recipe.create.support.containsKey('%MODEL_DIFFUSION%'), isTrue);
    expect(recipe.size, '1024x1536');
  });

  test(
    'draw things keeps image_gen_model when a comfy workflow id is leftover',
    () {
      final recipe = migrateImageStudioRecipe({
        'image_gen_backend': 'drawthings',
        'comfy_create_workflow_id': 'z_image_turbo',
        'image_gen_model': 'juggernautXL.safetensors',
      });
      expect(recipe.create.primaryFile, 'juggernautXL.safetensors');
      expect(recipe.backend, 'drawthings');
    },
  );

  test('comfy edit uses the edit diffusion choice, not image_gen_edit_model', () {
    final recipe = migrateImageStudioRecipe({
      'image_gen_backend': 'comfyui',
      'comfy_edit_workflow_id': 'qwen_image_edit',
      'image_gen_edit_model': 'qwen_image_bf16.safetensors',
      'comfy_edit_model_choices':
          '{"qwen_image_edit/%MODEL_DIFFUSION%":"qwen_image_edit.safetensors"}',
    });
    expect(recipe.edit.primaryFile, 'qwen_image_edit.safetensors');
    expect(
      recipe.edit.support['%MODEL_DIFFUSION%'],
      'qwen_image_edit.safetensors',
    );
  });

  test('an upload is active only while the workflow id is __uploaded__', () {
    final idle = migrateImageStudioRecipe({
      'image_gen_backend': 'comfyui',
      'comfy_create_workflow_id': 'z_image_turbo',
      'comfy_create_uploaded_workflow': '{"1":{"class_type":"KSampler"}}',
    });
    expect(idle.create.customWorkflow, isFalse);
    final active = migrateImageStudioRecipe({
      'image_gen_backend': 'comfyui',
      'comfy_create_workflow_id': '__uploaded__',
      'comfy_create_uploaded_workflow': '{"1":{"class_type":"KSampler"}}',
    });
    expect(active.create.workflowId, '__uploaded__');
    expect(active.create.customWorkflow, isTrue);
    expect(active.create.uploadedJson, contains('KSampler'));
  });

  test('a graph over 512 KiB stays out of the recipe blob', () {
    final huge = 'x' * (512 * 1024 + 1);
    final recipe = migrateImageStudioRecipe({
      'image_gen_backend': 'comfyui',
      'comfy_create_workflow_id': '__uploaded__',
      'comfy_create_uploaded_workflow': huge,
    });
    expect(recipe.encode().contains(huge), isFalse);
    expect(recipe.create.uploadExternal, isTrue);
    expect(recipe.create.externalUpload, huge);
    final reloaded = StudioRecipe.decode(recipe.encode());
    expect(reloaded.create.uploadExternal, isTrue);
    expect(reloaded.create.uploadedJson, isEmpty);
  });

  test('integer knobs and the single lora weight survive', () {
    final recipe = migrateImageStudioRecipe({
      'image_gen_steps': 8,
      'image_gen_cfg_scale': 1.5,
      'draw_things_sampler': 16,
      'image_gen_lora': 'detail.safetensors',
      'image_gen_lora_weight': 0.4,
      'image_gen_loras': '{',
    });
    expect(recipe.knobs['create/remote/image_gen_steps'], '8');
    expect(recipe.knobs['create/drawthings/draw_things_sampler'], '16');
    expect(recipe.knobs.containsKey('image_gen_steps'), isFalse);
    expect(recipe.loras.first['file'], 'detail.safetensors');
    expect(recipe.loras.first['weight'], 0.4);
  });

  test('json default backend is remote, and model roots are writable', () {
    final recipe = StudioRecipe.decode('{"create":{},"edit":{}}');
    expect(recipe.backend, 'remote');
    recipe.modelRoots['comfy'] = '/models';
    expect(recipe.modelRoots['comfy'], '/models');
  });

  test('size snaps to a multiple of 64 inside 256–2048', () {
    expect(snapStudioSize(1000, 1500), (width: 1024, height: 1472));
    expect(snapStudioSize(8, 9000), (width: 256, height: 2048));
  });

  test('draw things sampler labels stay on the wire values', () {
    String label(int value) =>
        kDrawThingsSamplers.firstWhere((s) => s.value == value).label;
    expect(label(10), 'Euler a Trailing');
    expect(label(16), 'DDIM Trailing');
    expect(label(17), 'UniPC Trailing');
  });
}
