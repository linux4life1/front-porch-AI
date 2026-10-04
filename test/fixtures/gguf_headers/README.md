# Real model headers, made small

Each `.gguf` here is the header of a real model file with the tokenizer's
long lists (tokens, scores, token types, merges) and the chat template taken
out. Everything else is as published: every other metadata value, and the
whole tensor table (each tensor's name, shape, type and where its data
starts). No weights are included. A file is 27 to 54 KB.

The `.json` beside each one says where the header came from, how big the real
file is, and what was measured from the real header: the exact bytes of all
tensors, of the blocks, of the MoE expert tensors, of the token embedding and
of the output layer.

`fixture_file_bytes` is the file size to give the reader with the small
header, so the last tensor comes out the size it has in the real file.

Why they exist: the estimator used to be checked only against headers built
by hand in the tests, and those used a key name no real model has
(`<arch>.sliding_window`; the real one is `<arch>.attention.sliding_window`).
Nothing failed, and sliding window was never detected on a real Gemma model.
These are the real thing.

Families covered: Gemma 4 (dense, and the 26B MoE), Qwen 3.8, Qwen 3.6 (dense,
MoE, and MoE with built-in draft heads), Qwen 3 (dense and MoE).
