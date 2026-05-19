#!/usr/bin/env python3
"""Generate a minimal FlatBuffer config for Draw Things gRPC testing."""

import flatbuffers
import sys
import os

# Add the generated Dart file to understand the field offsets
# But we'll use the Python flatbuffers library instead

# First, we need to generate Python code from the schema
# Or we can manually build the FlatBuffer

# Let's use the flatc compiler to generate Python code
def main():
    schema_path = '/Users/linux4life/dev/front-porch-AI/lib/services/grpc/draw_things.fbs'
    output_dir = '/tmp/dt_generated'
    os.makedirs(output_dir, exist_ok=True)
    
    # Generate Python code from schema
    import subprocess
    result = subprocess.run(
        ['flatc', '--python', '-o', output_dir, schema_path],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        print(f"flatc error: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    
    print(f"Generated Python code in {output_dir}")
    print(f"Files: {os.listdir(output_dir)}")
    
    # Now import and use the generated code
    sys.path.insert(0, output_dir)
    from draw_things import GenerationConfiguration, SamplerType, SeedMode
    
    builder = flatbuffers.Builder(0)
    
    # Build model string
    model = "illustriousdark_v4_f16.ckpt"
    model_offset = builder.CreateString(model)
    
    # Build GenerationConfiguration
    GenerationConfiguration.Start(builder)
    GenerationConfiguration.AddStartWidth(builder, 256)  # 1024/64
    GenerationConfiguration.AddStartHeight(builder, 256)  # 1024/64
    GenerationConfiguration.AddSeed(builder, 0)
    GenerationConfiguration.AddSteps(builder, 20)
    GenerationConfiguration.AddGuidanceScale(builder, 7.0)
    GenerationConfiguration.AddStrength(builder, 1.0)
    GenerationConfiguration.AddModel(builder, model_offset)
    GenerationConfiguration.AddSampler(builder, SamplerType.EulerA)
    GenerationConfiguration.AddBatchCount(builder, 1)
    GenerationConfiguration.AddBatchSize(builder, 1)
    GenerationConfiguration.AddSeedMode(builder, SeedMode.Legacy)
    GenerationConfiguration.AddRefinerStart(builder, 0.7)
    GenerationConfiguration.AddPreserveOriginalAfterInpaint(builder, True)
    GenerationConfiguration.AddResolutionDependentShift(builder, True)
    GenerationConfiguration.AddMaskBlur(builder, 0.0)
    GenerationConfiguration.AddSharpness(builder, 0.0)
    
    config_offset = GenerationConfiguration.End(builder)
    builder.Finish(config_offset)
    
    # Get the buffer
    buffer = builder.Output()
    
    # Write to file
    output_path = '/tmp/test_config_pb.bin'
    with open(output_path, 'wb') as f:
        f.write(buffer)
    
    print(f"FlatBuffer generated: {len(buffer)} bytes")
    print(f"Written to: {output_path}")
    print(f"Hex: {buffer.hex()[:100]}...")

if __name__ == '__main__':
    main()
