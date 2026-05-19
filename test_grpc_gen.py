#!/usr/bin/env python3
"""Build FlatBuffer for Draw Things gRPC generation test."""

import flatbuffers
import sys
import os
import base64

# Add the generated Python code to path
sys.path.insert(0, '/tmp/dt_generated2')
from GenerationConfiguration import GenerationConfiguration
from SamplerType import SamplerType
from SeedMode import SeedMode

def build_flatbuffer_config(model: str, width: int = 1024, height: int = 1024,
                            steps: int = 20, guidance_scale: float = 7.0,
                            strength: float = 1.0, seed: int = 0) -> bytes:
    """Build a FlatBuffer GenerationConfiguration using low-level API."""
    builder = flatbuffers.Builder(0)
    
    # Build model string
    model_offset = builder.CreateString(model)
    
    # Start object with enough slots for all fields we'll use
    # Each slot is 2 bytes, so we need 64 slots for 32 fields
    builder.StartObject(64)
    
    # Prepend fields in REVERSE order (last field first)
    # Field offsets are 2 * field_number
    
    # sharpness (field 16, offset 32)
    builder.PrependFloat32(0.0)
    builder.Slot(32)
    
    # mask_blur (field 15, offset 30)
    builder.PrependFloat32(0.0)
    builder.Slot(30)
    
    # resolution_dependent_shift (field 14, offset 28)
    builder.PrependBool(True)
    builder.Slot(28)
    
    # preserve_original_after_inpaint (field 13, offset 26)
    builder.PrependBool(True)
    builder.Slot(26)
    
    # refiner_start (field 12, offset 24)
    builder.PrependFloat32(0.7)
    builder.Slot(24)
    
    # seed_mode (field 11, offset 22)
    builder.PrependInt8(0)  # Legacy
    builder.Slot(22)
    
    # batch_size (field 10, offset 20)
    builder.PrependUint32(1)
    builder.Slot(20)
    
    # batch_count (field 9, offset 18)
    builder.PrependUint32(1)
    builder.Slot(18)
    
    # sampler (field 8, offset 16)
    builder.PrependInt8(1)  # EulerA
    builder.Slot(16)
    
    # model (field 7, offset 14)
    builder.PrependSOffsetTRelative(model_offset)
    builder.Slot(14)
    
    # strength (field 6, offset 12)
    builder.PrependFloat32(1.0)
    builder.Slot(12)
    
    # guidance_scale (field 5, offset 10)
    builder.PrependFloat32(7.0)
    builder.Slot(10)
    
    # steps (field 4, offset 8)
    builder.PrependUint32(steps)
    builder.Slot(8)
    
    # seed (field 3, offset 6)
    builder.PrependUint32(seed)
    builder.Slot(6)
    
    # start_height (field 2, offset 4)
    builder.PrependUint16(height // 64)
    builder.Slot(4)
    
    # start_width (field 1, offset 2)
    builder.PrependUint16(width // 64)
    builder.Slot(2)
    
    config_offset = builder.EndObject()
    builder.Finish(config_offset)
    
    return builder.Output()


def main():
    model = "flux_2_klein_9b_i8x.ckpt"
    print(f"Building FlatBuffer config for model: {model}")
    
    config_bytes = build_flatbuffer_config(model)
    print(f"FlatBuffer generated: {len(config_bytes)} bytes")
    print(f"Hex: {config_bytes.hex()[:100]}...")
    
    # Write to file
    output_path = '/tmp/test_config_pb3.bin'
    with open(output_path, 'wb') as f:
        f.write(config_bytes)
    print(f"Written to: {output_path}")
    
    # Now test with grpcurl
    print("\nTesting with grpcurl...")
    
    import subprocess
    
    # Read the FlatBuffer file
    with open(output_path, 'rb') as f:
        config_b64 = base64.b64encode(f.read()).decode('utf-8')
    
    # Create a JSON request with the FlatBuffer as base64
    grpcurl_cmd = [
        'grpcurl', '-connect-timeout', '5', '-max-time', '120',
        '-insecure',
        '-proto', '/Users/linux4life/dev/front-porch-AI/lib/services/grpc/image_service.proto',
        '-import-path', '/Users/linux4life/dev/front-porch-AI/lib/services/grpc',
        '-d', f'{{"prompt":"A beautiful sunset over the ocean","negativePrompt":"blurry, low quality","configuration":"{config_b64}","scaleFactor":1,"user":"test"}}',
        '127.0.0.1:7859',
        'ImageGenerationService.GenerateImage'
    ]
    
    print(f"Command: {' '.join(grpcurl_cmd)}")
    result = subprocess.run(
        grpcurl_cmd,
        capture_output=True, text=True, timeout=120
    )
    
    print(f"\nExit code: {result.returncode}")
    if result.stdout:
        print(f"Stdout ({len(result.stdout)} chars): {result.stdout[:1000]}")
    if result.stderr:
        print(f"Stderr ({len(result.stderr)} chars): {result.stderr[:1000]}")
    
    return result.returncode == 0


if __name__ == '__main__':
    success = main()
    sys.exit(0 if success else 1)
