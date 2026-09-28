import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/image/civitai_download.dart';
import 'package:front_porch_ai/services/image/civitai_oauth.dart';
import 'package:path/path.dart' as p;

void main() {
  test('a path escape is refused and does not leave the models root', () {
    expect(safeDownloadBasename('../../x.safetensors'), isNull);
    expect(safeDownloadBasename(r'..\x.safetensors'), isNull);
    expect(safeDownloadBasename('z_image.safetensors'), 'z_image.safetensors');
    expect(
      civitaiDownloadPath(
        root: '/models',
        folder: 'checkpoints',
        name: '../../x.safetensors',
      ),
      isNull,
    );
    final ok = civitaiDownloadPath(
      root: '/models',
      folder: 'loras',
      name: 'detail.safetensors',
    );
    expect(ok, p.join('/models', 'loras', 'detail.safetensors'));
    expect(pathStaysUnderRoot('/models', ok!), isTrue);
  });

  test('file type Model is not a checkpoint, and GGUF is refused on A1111', () {
    expect(
      civitaiSlotFolder(
        fromLoraSheet: true,
        civitaiType: 'Model',
        filename: 'style.safetensors',
      ),
      isNull,
    );
    expect(
      civitaiSlotFolder(
        fromLoraSheet: true,
        civitaiType: 'LoCon',
        filename: 'style.safetensors',
      ),
      'loras',
    );
    expect(
      civitaiSlotFolder(
        fromLoraSheet: false,
        civitaiType: 'Checkpoint',
        filename: 'z-image-Q5.gguf',
        backend: 'a1111',
      ),
      isNull,
    );
    expect(safeDownloadBasename('foo:bar.safetensors'), isNull);
    expect(
      civitaiDownloadPath(root: '', folder: 'loras', name: 'a.safetensors'),
      isNull,
    );
    expect(
      civitaiDownloadPath(root: '/models', folder: '.', name: 'a.safetensors'),
      isNull,
    );
    expect(
      civitaiSlotFolder(
        fromLoraSheet: true,
        civitaiType: 'LORA',
        filename: 'style.safetensors',
        backend: 'drawthings',
      ),
      isNull,
    );
  });

  test('a LoRA is not written into the diffusion folder', () {
    expect(
      civitaiSlotFolder(
        fromLoraSheet: false,
        civitaiType: 'LORA',
        filename: 'style.safetensors',
      ),
      isNull,
    );
    expect(
      civitaiSlotFolder(
        fromLoraSheet: true,
        civitaiType: 'LORA',
        filename: 'style.safetensors',
      ),
      'loras',
    );
  });

  test(
    'a checkpoint is not written into loras, and gguf uses diffusion_models',
    () {
      expect(
        civitaiSlotFolder(
          fromLoraSheet: true,
          civitaiType: 'Checkpoint',
          filename: 'juggernaut.safetensors',
        ),
        isNull,
      );
      expect(
        civitaiSlotFolder(
          fromLoraSheet: false,
          civitaiType: 'Checkpoint',
          filename: 'juggernaut.safetensors',
        ),
        'checkpoints',
      );
      expect(
        civitaiSlotFolder(
          fromLoraSheet: false,
          civitaiType: 'Checkpoint',
          filename: 'z-image-Q5.gguf',
        ),
        'diffusion_models',
      );
    },
  );

  test('each account has its own credential name', () {
    expect(civitaiCredentialKey('local'), 'civitai_credential_local');
    expect(civitaiCredentialKey('other'), 'civitai_credential_other');
    expect(() => civitaiCredentialKey('../x'), throwsArgumentError);
  });

  test('authorize url carries scope 5 and no token query', () {
    final url = civitaiAuthorizeUrl(
      clientId: 'front-porch',
      redirectUri: 'http://127.0.0.1:9/cb',
      state: 'abc',
      codeChallenge: pkceChallenge('verifier-value-verifier-value-verifier'),
    );
    final uri = Uri.parse(url);
    expect(uri.queryParameters['scope'], '5');
    expect(uri.queryParameters['code_challenge_method'], 'S256');
    expect(uri.queryParameters.containsKey('token'), isFalse);
    expect(uri.toString(), isNot(contains('Buzz')));
  });
}
