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

/// The exact size of a model's weights, sorted by where KoboldCpp can put
/// them. Summed from the file's own tensor table, so nothing here is an
/// estimate: it is what the file holds.
class GGUFWeights {
  const GGUFWeights({
    required this.total,
    required this.perBlock,
    required this.experts,
    required this.tokenEmbedding,
    required this.output,
    required this.other,
  });

  /// Every tensor in the file.
  final int total;

  /// Each block (`blk.N.*`), in order, expert weights included.
  final List<int> perBlock;

  /// The MoE expert weights inside the blocks. These are the tensors
  /// KoboldCpp keeps in system memory when experts stay off the card. 0 for
  /// a model that is not MoE.
  final int experts;

  /// The input embedding. KoboldCpp keeps it in system memory.
  final int tokenEmbedding;

  /// The output layer (`output.*`), when the file has one of its own.
  final int output;

  /// Everything else outside the blocks (norms, frequency tables).
  final int other;

  int get blocks => perBlock.fold(0, (sum, b) => sum + b);

  /// The tensors KoboldCpp's own rule moves to system memory for a MoE
  /// model: `blk.N.ffn_(up|down|gate|gate_up)_(ch|)exps`.
  static final RegExp _expert = RegExp(
    r'^blk\.\d+\.ffn_(up|down|gate|gate_up)_(ch|)exps',
  );
  static final RegExp _block = RegExp(r'^blk\.(\d+)\.');

  /// Sorts [sizes] (bytes per tensor name) into the groups above.
  factory GGUFWeights.fromTensorSizes(Map<String, int> sizes) {
    final blocks = <int, int>{};
    var experts = 0, tokenEmbedding = 0, output = 0, other = 0, total = 0;
    sizes.forEach((name, size) {
      total += size;
      final block = _block.firstMatch(name);
      if (block != null) {
        final index = int.parse(block.group(1)!);
        blocks[index] = (blocks[index] ?? 0) + size;
        if (_expert.hasMatch(name)) experts += size;
      } else if (name.startsWith('token_embd')) {
        tokenEmbedding += size;
      } else if (name.startsWith('output.')) {
        output += size;
      } else {
        other += size;
      }
    });
    final order = blocks.keys.toList()..sort();
    return GGUFWeights(
      total: total,
      perBlock: [for (final i in order) blocks[i]!],
      experts: experts,
      tokenEmbedding: tokenEmbedding,
      output: output,
      other: other,
    );
  }

  /// What sits on the graphics card with every block offloaded: the blocks
  /// (without the expert weights when those stay in system memory), the
  /// output layer and the small tensors around them. The input embedding
  /// is not counted: KoboldCpp keeps it in system memory.
  int gpuBytes({required bool expertsOnCpu}) =>
      blocks - (expertsOnCpu ? experts : 0) + output + other;
}
