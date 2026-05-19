// This is a generated file - do not edit.
//
// Generated from image_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use deviceTypeDescriptor instead')
const DeviceType$json = {
  '1': 'DeviceType',
  '2': [
    {'1': 'PHONE', '2': 0},
    {'1': 'TABLET', '2': 1},
    {'1': 'LAPTOP', '2': 2},
  ],
};

/// Descriptor for `DeviceType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List deviceTypeDescriptor = $convert.base64Decode(
    'CgpEZXZpY2VUeXBlEgkKBVBIT05FEAASCgoGVEFCTEVUEAESCgoGTEFQVE9QEAI=');

@$core.Deprecated('Use chunkStateDescriptor instead')
const ChunkState$json = {
  '1': 'ChunkState',
  '2': [
    {'1': 'LAST_CHUNK', '2': 0},
    {'1': 'MORE_CHUNKS', '2': 1},
  ],
};

/// Descriptor for `ChunkState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List chunkStateDescriptor = $convert.base64Decode(
    'CgpDaHVua1N0YXRlEg4KCkxBU1RfQ0hVTksQABIPCgtNT1JFX0NIVU5LUxAB');

@$core.Deprecated('Use echoRequestDescriptor instead')
const EchoRequest$json = {
  '1': 'EchoRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
    {
      '1': 'sharedSecret',
      '3': 2,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'sharedSecret',
      '17': true
    },
  ],
  '8': [
    {'1': '_sharedSecret'},
  ],
};

/// Descriptor for `EchoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List echoRequestDescriptor = $convert.base64Decode(
    'CgtFY2hvUmVxdWVzdBISCgRuYW1lGAEgASgJUgRuYW1lEicKDHNoYXJlZFNlY3JldBgCIAEoCU'
    'gAUgxzaGFyZWRTZWNyZXSIAQFCDwoNX3NoYXJlZFNlY3JldA==');

@$core.Deprecated('Use computeUnitThresholdDescriptor instead')
const ComputeUnitThreshold$json = {
  '1': 'ComputeUnitThreshold',
  '2': [
    {'1': 'community', '3': 1, '4': 1, '5': 1, '10': 'community'},
    {'1': 'plus', '3': 2, '4': 1, '5': 1, '10': 'plus'},
    {'1': 'expireAt', '3': 3, '4': 1, '5': 3, '10': 'expireAt'},
  ],
};

/// Descriptor for `ComputeUnitThreshold`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List computeUnitThresholdDescriptor = $convert.base64Decode(
    'ChRDb21wdXRlVW5pdFRocmVzaG9sZBIcCgljb21tdW5pdHkYASABKAFSCWNvbW11bml0eRISCg'
    'RwbHVzGAIgASgBUgRwbHVzEhoKCGV4cGlyZUF0GAMgASgDUghleHBpcmVBdA==');

@$core.Deprecated('Use echoReplyDescriptor instead')
const EchoReply$json = {
  '1': 'EchoReply',
  '2': [
    {'1': 'message', '3': 1, '4': 1, '5': 9, '10': 'message'},
    {'1': 'files', '3': 2, '4': 3, '5': 9, '10': 'files'},
    {
      '1': 'override',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.MetadataOverride',
      '9': 0,
      '10': 'override',
      '17': true
    },
    {
      '1': 'sharedSecretMissing',
      '3': 4,
      '4': 1,
      '5': 8,
      '10': 'sharedSecretMissing'
    },
    {
      '1': 'thresholds',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.ComputeUnitThreshold',
      '9': 1,
      '10': 'thresholds',
      '17': true
    },
    {'1': 'serverIdentifier', '3': 6, '4': 1, '5': 4, '10': 'serverIdentifier'},
  ],
  '8': [
    {'1': '_override'},
    {'1': '_thresholds'},
  ],
};

/// Descriptor for `EchoReply`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List echoReplyDescriptor = $convert.base64Decode(
    'CglFY2hvUmVwbHkSGAoHbWVzc2FnZRgBIAEoCVIHbWVzc2FnZRIUCgVmaWxlcxgCIAMoCVIFZm'
    'lsZXMSMgoIb3ZlcnJpZGUYAyABKAsyES5NZXRhZGF0YU92ZXJyaWRlSABSCG92ZXJyaWRliAEB'
    'EjAKE3NoYXJlZFNlY3JldE1pc3NpbmcYBCABKAhSE3NoYXJlZFNlY3JldE1pc3NpbmcSOgoKdG'
    'hyZXNob2xkcxgFIAEoCzIVLkNvbXB1dGVVbml0VGhyZXNob2xkSAFSCnRocmVzaG9sZHOIAQES'
    'KgoQc2VydmVySWRlbnRpZmllchgGIAEoBFIQc2VydmVySWRlbnRpZmllckILCglfb3ZlcnJpZG'
    'VCDQoLX3RocmVzaG9sZHM=');

@$core.Deprecated('Use fileListRequestDescriptor instead')
const FileListRequest$json = {
  '1': 'FileListRequest',
  '2': [
    {'1': 'files', '3': 1, '4': 3, '5': 9, '10': 'files'},
    {'1': 'filesWithHash', '3': 2, '4': 3, '5': 9, '10': 'filesWithHash'},
    {
      '1': 'sharedSecret',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 0,
      '10': 'sharedSecret',
      '17': true
    },
  ],
  '8': [
    {'1': '_sharedSecret'},
  ],
};

/// Descriptor for `FileListRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileListRequestDescriptor = $convert.base64Decode(
    'Cg9GaWxlTGlzdFJlcXVlc3QSFAoFZmlsZXMYASADKAlSBWZpbGVzEiQKDWZpbGVzV2l0aEhhc2'
    'gYAiADKAlSDWZpbGVzV2l0aEhhc2gSJwoMc2hhcmVkU2VjcmV0GAMgASgJSABSDHNoYXJlZFNl'
    'Y3JldIgBAUIPCg1fc2hhcmVkU2VjcmV0');

@$core.Deprecated('Use fileExistenceResponseDescriptor instead')
const FileExistenceResponse$json = {
  '1': 'FileExistenceResponse',
  '2': [
    {'1': 'files', '3': 1, '4': 3, '5': 9, '10': 'files'},
    {'1': 'existences', '3': 2, '4': 3, '5': 8, '10': 'existences'},
    {'1': 'hashes', '3': 3, '4': 3, '5': 12, '10': 'hashes'},
  ],
};

/// Descriptor for `FileExistenceResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileExistenceResponseDescriptor = $convert.base64Decode(
    'ChVGaWxlRXhpc3RlbmNlUmVzcG9uc2USFAoFZmlsZXMYASADKAlSBWZpbGVzEh4KCmV4aXN0ZW'
    '5jZXMYAiADKAhSCmV4aXN0ZW5jZXMSFgoGaGFzaGVzGAMgAygMUgZoYXNoZXM=');

@$core.Deprecated('Use metadataOverrideDescriptor instead')
const MetadataOverride$json = {
  '1': 'MetadataOverride',
  '2': [
    {'1': 'models', '3': 1, '4': 1, '5': 12, '10': 'models'},
    {'1': 'loras', '3': 2, '4': 1, '5': 12, '10': 'loras'},
    {'1': 'controlNets', '3': 3, '4': 1, '5': 12, '10': 'controlNets'},
    {
      '1': 'textualInversions',
      '3': 4,
      '4': 1,
      '5': 12,
      '10': 'textualInversions'
    },
    {'1': 'upscalers', '3': 5, '4': 1, '5': 12, '10': 'upscalers'},
  ],
};

/// Descriptor for `MetadataOverride`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List metadataOverrideDescriptor = $convert.base64Decode(
    'ChBNZXRhZGF0YU92ZXJyaWRlEhYKBm1vZGVscxgBIAEoDFIGbW9kZWxzEhQKBWxvcmFzGAIgAS'
    'gMUgVsb3JhcxIgCgtjb250cm9sTmV0cxgDIAEoDFILY29udHJvbE5ldHMSLAoRdGV4dHVhbElu'
    'dmVyc2lvbnMYBCABKAxSEXRleHR1YWxJbnZlcnNpb25zEhwKCXVwc2NhbGVycxgFIAEoDFIJdX'
    'BzY2FsZXJz');

@$core.Deprecated('Use imageGenerationRequestDescriptor instead')
const ImageGenerationRequest$json = {
  '1': 'ImageGenerationRequest',
  '2': [
    {'1': 'image', '3': 1, '4': 1, '5': 12, '9': 0, '10': 'image', '17': true},
    {'1': 'scaleFactor', '3': 2, '4': 1, '5': 5, '10': 'scaleFactor'},
    {'1': 'mask', '3': 3, '4': 1, '5': 12, '9': 1, '10': 'mask', '17': true},
    {'1': 'hints', '3': 4, '4': 3, '5': 11, '6': '.HintProto', '10': 'hints'},
    {'1': 'prompt', '3': 5, '4': 1, '5': 9, '10': 'prompt'},
    {'1': 'negativePrompt', '3': 6, '4': 1, '5': 9, '10': 'negativePrompt'},
    {'1': 'configuration', '3': 7, '4': 1, '5': 12, '10': 'configuration'},
    {
      '1': 'override',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.MetadataOverride',
      '10': 'override'
    },
    {'1': 'keywords', '3': 9, '4': 3, '5': 9, '10': 'keywords'},
    {'1': 'user', '3': 10, '4': 1, '5': 9, '10': 'user'},
    {
      '1': 'device',
      '3': 11,
      '4': 1,
      '5': 14,
      '6': '.DeviceType',
      '10': 'device'
    },
    {'1': 'contents', '3': 12, '4': 3, '5': 12, '10': 'contents'},
    {
      '1': 'sharedSecret',
      '3': 13,
      '4': 1,
      '5': 9,
      '9': 2,
      '10': 'sharedSecret',
      '17': true
    },
    {'1': 'chunked', '3': 14, '4': 1, '5': 8, '10': 'chunked'},
  ],
  '8': [
    {'1': '_image'},
    {'1': '_mask'},
    {'1': '_sharedSecret'},
  ],
};

/// Descriptor for `ImageGenerationRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageGenerationRequestDescriptor = $convert.base64Decode(
    'ChZJbWFnZUdlbmVyYXRpb25SZXF1ZXN0EhkKBWltYWdlGAEgASgMSABSBWltYWdliAEBEiAKC3'
    'NjYWxlRmFjdG9yGAIgASgFUgtzY2FsZUZhY3RvchIXCgRtYXNrGAMgASgMSAFSBG1hc2uIAQES'
    'IAoFaGludHMYBCADKAsyCi5IaW50UHJvdG9SBWhpbnRzEhYKBnByb21wdBgFIAEoCVIGcHJvbX'
    'B0EiYKDm5lZ2F0aXZlUHJvbXB0GAYgASgJUg5uZWdhdGl2ZVByb21wdBIkCg1jb25maWd1cmF0'
    'aW9uGAcgASgMUg1jb25maWd1cmF0aW9uEi0KCG92ZXJyaWRlGAggASgLMhEuTWV0YWRhdGFPdm'
    'VycmlkZVIIb3ZlcnJpZGUSGgoIa2V5d29yZHMYCSADKAlSCGtleXdvcmRzEhIKBHVzZXIYCiAB'
    'KAlSBHVzZXISIwoGZGV2aWNlGAsgASgOMgsuRGV2aWNlVHlwZVIGZGV2aWNlEhoKCGNvbnRlbn'
    'RzGAwgAygMUghjb250ZW50cxInCgxzaGFyZWRTZWNyZXQYDSABKAlIAlIMc2hhcmVkU2VjcmV0'
    'iAEBEhgKB2NodW5rZWQYDiABKAhSB2NodW5rZWRCCAoGX2ltYWdlQgcKBV9tYXNrQg8KDV9zaG'
    'FyZWRTZWNyZXQ=');

@$core.Deprecated('Use hintProtoDescriptor instead')
const HintProto$json = {
  '1': 'HintProto',
  '2': [
    {'1': 'hintType', '3': 1, '4': 1, '5': 9, '10': 'hintType'},
    {
      '1': 'tensors',
      '3': 2,
      '4': 3,
      '5': 11,
      '6': '.TensorAndWeight',
      '10': 'tensors'
    },
  ],
};

/// Descriptor for `HintProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hintProtoDescriptor = $convert.base64Decode(
    'CglIaW50UHJvdG8SGgoIaGludFR5cGUYASABKAlSCGhpbnRUeXBlEioKB3RlbnNvcnMYAiADKA'
    'syEC5UZW5zb3JBbmRXZWlnaHRSB3RlbnNvcnM=');

@$core.Deprecated('Use tensorAndWeightDescriptor instead')
const TensorAndWeight$json = {
  '1': 'TensorAndWeight',
  '2': [
    {'1': 'tensor', '3': 1, '4': 1, '5': 12, '10': 'tensor'},
    {'1': 'weight', '3': 2, '4': 1, '5': 2, '10': 'weight'},
  ],
};

/// Descriptor for `TensorAndWeight`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List tensorAndWeightDescriptor = $convert.base64Decode(
    'Cg9UZW5zb3JBbmRXZWlnaHQSFgoGdGVuc29yGAEgASgMUgZ0ZW5zb3ISFgoGd2VpZ2h0GAIgAS'
    'gCUgZ3ZWlnaHQ=');

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto$json = {
  '1': 'ImageGenerationSignpostProto',
  '2': [
    {
      '1': 'textEncoded',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.TextEncoded',
      '9': 0,
      '10': 'textEncoded'
    },
    {
      '1': 'imageEncoded',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.ImageEncoded',
      '9': 0,
      '10': 'imageEncoded'
    },
    {
      '1': 'sampling',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.Sampling',
      '9': 0,
      '10': 'sampling'
    },
    {
      '1': 'imageDecoded',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.ImageDecoded',
      '9': 0,
      '10': 'imageDecoded'
    },
    {
      '1': 'secondPassImageEncoded',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.SecondPassImageEncoded',
      '9': 0,
      '10': 'secondPassImageEncoded'
    },
    {
      '1': 'secondPassSampling',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.SecondPassSampling',
      '9': 0,
      '10': 'secondPassSampling'
    },
    {
      '1': 'secondPassImageDecoded',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.SecondPassImageDecoded',
      '9': 0,
      '10': 'secondPassImageDecoded'
    },
    {
      '1': 'faceRestored',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.FaceRestored',
      '9': 0,
      '10': 'faceRestored'
    },
    {
      '1': 'imageUpscaled',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto.ImageUpscaled',
      '9': 0,
      '10': 'imageUpscaled'
    },
  ],
  '3': [
    ImageGenerationSignpostProto_TextEncoded$json,
    ImageGenerationSignpostProto_ImageEncoded$json,
    ImageGenerationSignpostProto_Sampling$json,
    ImageGenerationSignpostProto_ImageDecoded$json,
    ImageGenerationSignpostProto_SecondPassImageEncoded$json,
    ImageGenerationSignpostProto_SecondPassSampling$json,
    ImageGenerationSignpostProto_SecondPassImageDecoded$json,
    ImageGenerationSignpostProto_FaceRestored$json,
    ImageGenerationSignpostProto_ImageUpscaled$json
  ],
  '8': [
    {'1': 'signpost'},
  ],
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_TextEncoded$json = {
  '1': 'TextEncoded',
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_ImageEncoded$json = {
  '1': 'ImageEncoded',
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_Sampling$json = {
  '1': 'Sampling',
  '2': [
    {'1': 'step', '3': 1, '4': 1, '5': 5, '10': 'step'},
  ],
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_ImageDecoded$json = {
  '1': 'ImageDecoded',
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_SecondPassImageEncoded$json = {
  '1': 'SecondPassImageEncoded',
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_SecondPassSampling$json = {
  '1': 'SecondPassSampling',
  '2': [
    {'1': 'step', '3': 1, '4': 1, '5': 5, '10': 'step'},
  ],
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_SecondPassImageDecoded$json = {
  '1': 'SecondPassImageDecoded',
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_FaceRestored$json = {
  '1': 'FaceRestored',
};

@$core.Deprecated('Use imageGenerationSignpostProtoDescriptor instead')
const ImageGenerationSignpostProto_ImageUpscaled$json = {
  '1': 'ImageUpscaled',
};

/// Descriptor for `ImageGenerationSignpostProto`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageGenerationSignpostProtoDescriptor = $convert.base64Decode(
    'ChxJbWFnZUdlbmVyYXRpb25TaWducG9zdFByb3RvEk0KC3RleHRFbmNvZGVkGAEgASgLMikuSW'
    '1hZ2VHZW5lcmF0aW9uU2lnbnBvc3RQcm90by5UZXh0RW5jb2RlZEgAUgt0ZXh0RW5jb2RlZBJQ'
    'CgxpbWFnZUVuY29kZWQYAiABKAsyKi5JbWFnZUdlbmVyYXRpb25TaWducG9zdFByb3RvLkltYW'
    'dlRW5jb2RlZEgAUgxpbWFnZUVuY29kZWQSRAoIc2FtcGxpbmcYAyABKAsyJi5JbWFnZUdlbmVy'
    'YXRpb25TaWducG9zdFByb3RvLlNhbXBsaW5nSABSCHNhbXBsaW5nElAKDGltYWdlRGVjb2RlZB'
    'gEIAEoCzIqLkltYWdlR2VuZXJhdGlvblNpZ25wb3N0UHJvdG8uSW1hZ2VEZWNvZGVkSABSDGlt'
    'YWdlRGVjb2RlZBJuChZzZWNvbmRQYXNzSW1hZ2VFbmNvZGVkGAUgASgLMjQuSW1hZ2VHZW5lcm'
    'F0aW9uU2lnbnBvc3RQcm90by5TZWNvbmRQYXNzSW1hZ2VFbmNvZGVkSABSFnNlY29uZFBhc3NJ'
    'bWFnZUVuY29kZWQSYgoSc2Vjb25kUGFzc1NhbXBsaW5nGAYgASgLMjAuSW1hZ2VHZW5lcmF0aW'
    '9uU2lnbnBvc3RQcm90by5TZWNvbmRQYXNzU2FtcGxpbmdIAFISc2Vjb25kUGFzc1NhbXBsaW5n'
    'Em4KFnNlY29uZFBhc3NJbWFnZURlY29kZWQYByABKAsyNC5JbWFnZUdlbmVyYXRpb25TaWducG'
    '9zdFByb3RvLlNlY29uZFBhc3NJbWFnZURlY29kZWRIAFIWc2Vjb25kUGFzc0ltYWdlRGVjb2Rl'
    'ZBJQCgxmYWNlUmVzdG9yZWQYCCABKAsyKi5JbWFnZUdlbmVyYXRpb25TaWducG9zdFByb3RvLk'
    'ZhY2VSZXN0b3JlZEgAUgxmYWNlUmVzdG9yZWQSUwoNaW1hZ2VVcHNjYWxlZBgJIAEoCzIrLklt'
    'YWdlR2VuZXJhdGlvblNpZ25wb3N0UHJvdG8uSW1hZ2VVcHNjYWxlZEgAUg1pbWFnZVVwc2NhbG'
    'VkGg0KC1RleHRFbmNvZGVkGg4KDEltYWdlRW5jb2RlZBoeCghTYW1wbGluZxISCgRzdGVwGAEg'
    'ASgFUgRzdGVwGg4KDEltYWdlRGVjb2RlZBoYChZTZWNvbmRQYXNzSW1hZ2VFbmNvZGVkGigKEl'
    'NlY29uZFBhc3NTYW1wbGluZxISCgRzdGVwGAEgASgFUgRzdGVwGhgKFlNlY29uZFBhc3NJbWFn'
    'ZURlY29kZWQaDgoMRmFjZVJlc3RvcmVkGg8KDUltYWdlVXBzY2FsZWRCCgoIc2lnbnBvc3Q=');

@$core.Deprecated('Use remoteDownloadResponseDescriptor instead')
const RemoteDownloadResponse$json = {
  '1': 'RemoteDownloadResponse',
  '2': [
    {'1': 'bytesReceived', '3': 1, '4': 1, '5': 3, '10': 'bytesReceived'},
    {'1': 'bytesExpected', '3': 2, '4': 1, '5': 3, '10': 'bytesExpected'},
    {'1': 'item', '3': 3, '4': 1, '5': 5, '10': 'item'},
    {'1': 'itemsExpected', '3': 4, '4': 1, '5': 5, '10': 'itemsExpected'},
    {'1': 'tag', '3': 5, '4': 1, '5': 9, '10': 'tag'},
  ],
};

/// Descriptor for `RemoteDownloadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List remoteDownloadResponseDescriptor = $convert.base64Decode(
    'ChZSZW1vdGVEb3dubG9hZFJlc3BvbnNlEiQKDWJ5dGVzUmVjZWl2ZWQYASABKANSDWJ5dGVzUm'
    'VjZWl2ZWQSJAoNYnl0ZXNFeHBlY3RlZBgCIAEoA1INYnl0ZXNFeHBlY3RlZBISCgRpdGVtGAMg'
    'ASgFUgRpdGVtEiQKDWl0ZW1zRXhwZWN0ZWQYBCABKAVSDWl0ZW1zRXhwZWN0ZWQSEAoDdGFnGA'
    'UgASgJUgN0YWc=');

@$core.Deprecated('Use imageGenerationResponseDescriptor instead')
const ImageGenerationResponse$json = {
  '1': 'ImageGenerationResponse',
  '2': [
    {'1': 'generatedImages', '3': 1, '4': 3, '5': 12, '10': 'generatedImages'},
    {
      '1': 'currentSignpost',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.ImageGenerationSignpostProto',
      '9': 0,
      '10': 'currentSignpost',
      '17': true
    },
    {
      '1': 'signposts',
      '3': 3,
      '4': 3,
      '5': 11,
      '6': '.ImageGenerationSignpostProto',
      '10': 'signposts'
    },
    {
      '1': 'previewImage',
      '3': 4,
      '4': 1,
      '5': 12,
      '9': 1,
      '10': 'previewImage',
      '17': true
    },
    {
      '1': 'scaleFactor',
      '3': 5,
      '4': 1,
      '5': 5,
      '9': 2,
      '10': 'scaleFactor',
      '17': true
    },
    {'1': 'tags', '3': 6, '4': 3, '5': 9, '10': 'tags'},
    {
      '1': 'downloadSize',
      '3': 7,
      '4': 1,
      '5': 3,
      '9': 3,
      '10': 'downloadSize',
      '17': true
    },
    {
      '1': 'chunkState',
      '3': 8,
      '4': 1,
      '5': 14,
      '6': '.ChunkState',
      '10': 'chunkState'
    },
    {
      '1': 'remoteDownload',
      '3': 9,
      '4': 1,
      '5': 11,
      '6': '.RemoteDownloadResponse',
      '9': 4,
      '10': 'remoteDownload',
      '17': true
    },
    {'1': 'generatedAudio', '3': 10, '4': 3, '5': 12, '10': 'generatedAudio'},
  ],
  '8': [
    {'1': '_currentSignpost'},
    {'1': '_previewImage'},
    {'1': '_scaleFactor'},
    {'1': '_downloadSize'},
    {'1': '_remoteDownload'},
  ],
};

/// Descriptor for `ImageGenerationResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List imageGenerationResponseDescriptor = $convert.base64Decode(
    'ChdJbWFnZUdlbmVyYXRpb25SZXNwb25zZRIoCg9nZW5lcmF0ZWRJbWFnZXMYASADKAxSD2dlbm'
    'VyYXRlZEltYWdlcxJMCg9jdXJyZW50U2lnbnBvc3QYAiABKAsyHS5JbWFnZUdlbmVyYXRpb25T'
    'aWducG9zdFByb3RvSABSD2N1cnJlbnRTaWducG9zdIgBARI7CglzaWducG9zdHMYAyADKAsyHS'
    '5JbWFnZUdlbmVyYXRpb25TaWducG9zdFByb3RvUglzaWducG9zdHMSJwoMcHJldmlld0ltYWdl'
    'GAQgASgMSAFSDHByZXZpZXdJbWFnZYgBARIlCgtzY2FsZUZhY3RvchgFIAEoBUgCUgtzY2FsZU'
    'ZhY3RvcogBARISCgR0YWdzGAYgAygJUgR0YWdzEicKDGRvd25sb2FkU2l6ZRgHIAEoA0gDUgxk'
    'b3dubG9hZFNpemWIAQESKwoKY2h1bmtTdGF0ZRgIIAEoDjILLkNodW5rU3RhdGVSCmNodW5rU3'
    'RhdGUSRAoOcmVtb3RlRG93bmxvYWQYCSABKAsyFy5SZW1vdGVEb3dubG9hZFJlc3BvbnNlSARS'
    'DnJlbW90ZURvd25sb2FkiAEBEiYKDmdlbmVyYXRlZEF1ZGlvGAogAygMUg5nZW5lcmF0ZWRBdW'
    'Rpb0ISChBfY3VycmVudFNpZ25wb3N0Qg8KDV9wcmV2aWV3SW1hZ2VCDgoMX3NjYWxlRmFjdG9y'
    'Qg8KDV9kb3dubG9hZFNpemVCEQoPX3JlbW90ZURvd25sb2Fk');

@$core.Deprecated('Use fileChunkDescriptor instead')
const FileChunk$json = {
  '1': 'FileChunk',
  '2': [
    {'1': 'content', '3': 1, '4': 1, '5': 12, '10': 'content'},
    {'1': 'filename', '3': 2, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'offset', '3': 3, '4': 1, '5': 3, '10': 'offset'},
  ],
};

/// Descriptor for `FileChunk`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileChunkDescriptor = $convert.base64Decode(
    'CglGaWxlQ2h1bmsSGAoHY29udGVudBgBIAEoDFIHY29udGVudBIaCghmaWxlbmFtZRgCIAEoCV'
    'IIZmlsZW5hbWUSFgoGb2Zmc2V0GAMgASgDUgZvZmZzZXQ=');

@$core.Deprecated('Use initUploadRequestDescriptor instead')
const InitUploadRequest$json = {
  '1': 'InitUploadRequest',
  '2': [
    {'1': 'filename', '3': 1, '4': 1, '5': 9, '10': 'filename'},
    {'1': 'sha256', '3': 2, '4': 1, '5': 12, '10': 'sha256'},
    {'1': 'totalSize', '3': 3, '4': 1, '5': 3, '10': 'totalSize'},
  ],
};

/// Descriptor for `InitUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List initUploadRequestDescriptor = $convert.base64Decode(
    'ChFJbml0VXBsb2FkUmVxdWVzdBIaCghmaWxlbmFtZRgBIAEoCVIIZmlsZW5hbWUSFgoGc2hhMj'
    'U2GAIgASgMUgZzaGEyNTYSHAoJdG90YWxTaXplGAMgASgDUgl0b3RhbFNpemU=');

@$core.Deprecated('Use uploadResponseDescriptor instead')
const UploadResponse$json = {
  '1': 'UploadResponse',
  '2': [
    {
      '1': 'chunkUploadSuccess',
      '3': 1,
      '4': 1,
      '5': 8,
      '10': 'chunkUploadSuccess'
    },
    {'1': 'receivedOffset', '3': 2, '4': 1, '5': 3, '10': 'receivedOffset'},
    {'1': 'message', '3': 3, '4': 1, '5': 9, '10': 'message'},
    {'1': 'filename', '3': 4, '4': 1, '5': 9, '10': 'filename'},
  ],
};

/// Descriptor for `UploadResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List uploadResponseDescriptor = $convert.base64Decode(
    'Cg5VcGxvYWRSZXNwb25zZRIuChJjaHVua1VwbG9hZFN1Y2Nlc3MYASABKAhSEmNodW5rVXBsb2'
    'FkU3VjY2VzcxImCg5yZWNlaXZlZE9mZnNldBgCIAEoA1IOcmVjZWl2ZWRPZmZzZXQSGAoHbWVz'
    'c2FnZRgDIAEoCVIHbWVzc2FnZRIaCghmaWxlbmFtZRgEIAEoCVIIZmlsZW5hbWU=');

@$core.Deprecated('Use fileUploadRequestDescriptor instead')
const FileUploadRequest$json = {
  '1': 'FileUploadRequest',
  '2': [
    {
      '1': 'initRequest',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.InitUploadRequest',
      '9': 0,
      '10': 'initRequest'
    },
    {
      '1': 'chunk',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.FileChunk',
      '9': 0,
      '10': 'chunk'
    },
    {
      '1': 'sharedSecret',
      '3': 3,
      '4': 1,
      '5': 9,
      '9': 1,
      '10': 'sharedSecret',
      '17': true
    },
  ],
  '8': [
    {'1': 'request'},
    {'1': '_sharedSecret'},
  ],
};

/// Descriptor for `FileUploadRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List fileUploadRequestDescriptor = $convert.base64Decode(
    'ChFGaWxlVXBsb2FkUmVxdWVzdBI2Cgtpbml0UmVxdWVzdBgBIAEoCzISLkluaXRVcGxvYWRSZX'
    'F1ZXN0SABSC2luaXRSZXF1ZXN0EiIKBWNodW5rGAIgASgLMgouRmlsZUNodW5rSABSBWNodW5r'
    'EicKDHNoYXJlZFNlY3JldBgDIAEoCUgBUgxzaGFyZWRTZWNyZXSIAQFCCQoHcmVxdWVzdEIPCg'
    '1fc2hhcmVkU2VjcmV0');

@$core.Deprecated('Use pubkeyRequestDescriptor instead')
const PubkeyRequest$json = {
  '1': 'PubkeyRequest',
  '2': [
    {'1': 'name', '3': 1, '4': 1, '5': 9, '10': 'name'},
  ],
};

/// Descriptor for `PubkeyRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pubkeyRequestDescriptor =
    $convert.base64Decode('Cg1QdWJrZXlSZXF1ZXN0EhIKBG5hbWUYASABKAlSBG5hbWU=');

@$core.Deprecated('Use pubkeyResponseDescriptor instead')
const PubkeyResponse$json = {
  '1': 'PubkeyResponse',
  '2': [
    {'1': 'message', '3': 1, '4': 1, '5': 9, '10': 'message'},
    {'1': 'pubkey', '3': 2, '4': 1, '5': 9, '10': 'pubkey'},
  ],
};

/// Descriptor for `PubkeyResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pubkeyResponseDescriptor = $convert.base64Decode(
    'Cg5QdWJrZXlSZXNwb25zZRIYCgdtZXNzYWdlGAEgASgJUgdtZXNzYWdlEhYKBnB1YmtleRgCIA'
    'EoCVIGcHVia2V5');

@$core.Deprecated('Use hoursRequestDescriptor instead')
const HoursRequest$json = {
  '1': 'HoursRequest',
};

/// Descriptor for `HoursRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hoursRequestDescriptor =
    $convert.base64Decode('CgxIb3Vyc1JlcXVlc3Q=');

@$core.Deprecated('Use hoursResponseDescriptor instead')
const HoursResponse$json = {
  '1': 'HoursResponse',
  '2': [
    {
      '1': 'thresholds',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.ComputeUnitThreshold',
      '10': 'thresholds'
    },
  ],
};

/// Descriptor for `HoursResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hoursResponseDescriptor = $convert.base64Decode(
    'Cg1Ib3Vyc1Jlc3BvbnNlEjUKCnRocmVzaG9sZHMYASABKAsyFS5Db21wdXRlVW5pdFRocmVzaG'
    '9sZFIKdGhyZXNob2xkcw==');
