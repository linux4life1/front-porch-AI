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

// The ONE applier. Everything that decides WHAT happened lives in the eval;
// everything that decides how state changes lives here.

part of 'pockets.dart';

/// cards. No-op ops emit nothing; passing null costs nothing.
/// cards. No-op ops emit nothing; passing null costs nothing.
List<String> applyPocketOps(
  Pockets p,
  Iterable<PocketOpReport> ops, {
  void Function(String to, PocketItem item)? onTransfer,
  int day = 0,
  List<PocketEvent>? events,
}) {
  final receipts = <String>[];

  // Housekeeping before ops, so everything below acts on the record as the
  // story sees it: yesterday's set-aside clothes are already gone.
  p.expireSetAside(day);

  int find(List<PocketItem> list, String name) =>
      list.indexWhere((i) => sameItem(i.name, name));
  int findAside(String name) =>
      p.setAside.indexWhere((e) => sameItem(e.item.name, name));

  void capTo(List<PocketItem> list, int max) {
    // Trim the OLDEST, not the newest: the thing just picked up is the thing
    // the scene is about.
    while (list.length > max) {
      list.removeAt(0);
    }
  }

  void park(PocketItem item, {required bool clothing}) {
    p.setAside.add(SetAsideItem(item, clothing: clothing, day: day));
    while (p.setAside.length > kMaxSetAside) {
      // Evict CLOTHING first — it expires at the next story morning anyway,
      // while a possession is under the "never vanishes" promise. Trimming
      // strictly oldest-first let tonight's bulk undress silently evict the
      // mysterious letter parked three days ago (hostile review 2026-08-11).
      final firstClothing = p.setAside.indexWhere((e) => e.clothing);
      p.setAside.removeAt(firstClothing != -1 ? firstClothing : 0);
    }
  }

  void undressAll() {
    for (final it in p.worn) {
      park(it, clothing: true);
      receipts.add('took off: ${it.name}');
      events?.add(
        PocketEvent(
          kind: PocketOpKind.remove,
          item: it.name,
          clothing: true,
          bulk: true,
        ),
      );
    }
    p.worn.clear();
    for (final it in p.carrying) {
      park(it, clothing: false);
      receipts.add('set aside: ${it.name}');
      events?.add(
        PocketEvent(kind: PocketOpKind.remove, item: it.name, bulk: true),
      );
    }
    p.carrying.clear();
  }

  for (final op in ops) {
    switch (op.kind) {
      case PocketOpKind.wear:
        // Bulk-out, mirroring remove's bulk-in: "they get dressed" arrives
        // as ONE wear op naming "clothes", and the rubric's own "remove of
        // 'clothes' means all of it" teaches models the symmetric report.
        // Without this branch the applier minted a literal garment named
        // "clothes" into the worn list — garbage the record then displayed
        // AND injected (hostile review, 2026-08-11). Re-dress from the
        // set-aside pile's clothing; with nothing set aside there is
        // nothing to put on, and inventing an item is exactly the failure
        // the no-op rule exists to prevent.
        if (isEmptyWardrobeRef(op.item)) {
          // Nude is remove, not a garment named "nothing".
          if (p.worn.isEmpty && p.carrying.isEmpty) break;
          undressAll();
          break;
        }
        if (isGenericClothingRef(op.item)) {
          final backOn = [
            for (final e in p.setAside)
              if (e.clothing) e,
          ];
          for (final e in backOn) {
            p.setAside.remove(e);
            p.worn.add(e.item);
            receipts.add('put on: ${e.item.name}');
            events?.add(
              PocketEvent(kind: op.kind, item: e.item.name, clothing: true),
            );
          }
          capTo(p.worn, kMaxWorn);
          break;
        }
        final alreadyWorn = find(p.worn, op.item);
        if (alreadyWorn != -1) {
          // Already on — but the model may be reporting a CHANGE to it ("their
          // dress is now torn"), and dropping that on the floor was silent
          // data loss (Grok, 2026-08-07). Nothing to say without a state.
          if (op.state.isNotEmpty && p.worn[alreadyWorn].state != op.state) {
            p.worn[alreadyWorn] = p.worn[alreadyWorn].withState(op.state);
            receipts.add('${op.item}: ${op.state}');
          }
          break;
        }
        final c = find(p.carrying, op.item);
        final s = c == -1 ? findAside(op.item) : -1;
        // Carrying first, then the set-aside pile (the shower case: their
        // clothes are right there), then a genuinely new garment.
        final item = c != -1
            ? p.carrying.removeAt(c)
            : s != -1
            ? p.setAside.removeAt(s).item
            : PocketItem.clean(op.item, state: op.state);
        p.worn.add(op.state.isEmpty ? item : item.withState(op.state));
        capTo(p.worn, kMaxWorn);
        receipts.add('put on: ${op.item}');
        events?.add(
          PocketEvent(kind: op.kind, item: item.name, clothing: true),
        );

      case PocketOpKind.remove:
        // Clothing taken off goes to SET ASIDE, not to carrying and not
        // into thin air. The 2026-08-11 morning ruling ("remove deletes")
        // was superseded the same day by the approved set-aside design: a
        // mid-scene shower needs the outfit recoverable ("their clothes are
        // right there"), while the overnight case still honours the ruling
        // — clothing entries expire at the next story morning, so tomorrow
        // they dress fresh via wear ops and yesterday's shirt is gone.
        if (isGenericClothingRef(op.item)) {
          // "They undress" — the whole outfit comes off, and what they were
          // carrying lands beside it (pockets are in the clothes; nobody
          // showers holding their phone). Possessions park as
          // non-expiring: the keys are still on the nightstand tomorrow.
          undressAll();
          break;
        }
        final w = find(p.worn, op.item);
        if (w == -1) break;
        final removed = p.worn.removeAt(w);
        park(removed, clothing: true);
        receipts.add('took off: ${op.item}');
        events?.add(
          PocketEvent(kind: op.kind, item: removed.name, clothing: true),
        );

      case PocketOpKind.setdown:
        // Put down nearby, still theirs — the mid-scene sibling of the bulk
        // undress ("they set their bag by the door"). Before this op existed
        // the model's only honest choices were `drop` (which DELETES the
        // bag) or silence (they "carry" it all evening) — the same
        // data-loss shape as the undress bug, in miniature.
        if (isGenericThingsRef(op.item)) {
          // "They set their things down" — everything in hand goes beside
          // them. Carried only: undressing is remove's business.
          for (final it in p.carrying) {
            park(it, clothing: false);
            receipts.add('set aside: ${it.name}');
            events?.add(
              PocketEvent(kind: op.kind, item: it.name, where: op.where),
            );
          }
          p.carrying.clear();
          break;
        }
        final sc = find(p.carrying, op.item);
        if (sc != -1) {
          final down = p.carrying.removeAt(sc);
          park(down, clothing: false);
          receipts.add('set aside: ${op.item}');
          events?.add(
            PocketEvent(kind: op.kind, item: down.name, where: op.where),
          );
          break;
        }
        // A worn thing set down (hat on the table) is clothing taken off.
        final sw = find(p.worn, op.item);
        if (sw == -1) break;
        final downWorn = p.worn.removeAt(sw);
        park(downWorn, clothing: true);
        receipts.add('set aside: ${op.item}');
        events?.add(
          PocketEvent(
            kind: op.kind,
            item: downWorn.name,
            where: op.where,
            clothing: true,
          ),
        );

      case PocketOpKind.pickup:
        if (find(p.carrying, op.item) != -1 || find(p.worn, op.item) != -1) {
          break;
        }
        // The set-aside pile first — taking back their own keys is not
        // acquiring new ones, and the condition rides along. A NEW state on
        // the op updates it, the same rule wear's retrieval follows (the
        // two paths disagreed for no reason — hostile review 2026-08-11).
        final sa = findAside(op.item);
        final got = sa != -1
            ? p.setAside.removeAt(sa).item
            : PocketItem.clean(op.item, state: op.state);
        p.carrying.add(op.state.isEmpty ? got : got.withState(op.state));
        capTo(p.carrying, kMaxCarrying);
        receipts.add('picked up: ${op.item}');
        events?.add(PocketEvent(kind: PocketOpKind.pickup, item: got.name));

      // `give` used to be half a transfer: the item left the giver and reached
      // nobody, so Alice handing Bob the keys left Bob's record untouched. The
      // reason was real — resolving a free-text name the model chose to a
      // member record, and putting the keys in the WRONG character's pocket, is
      // a worse failure than not moving them, because it is invisible AND
      // wrong. The fix is not to guess better; it is to only accept a name the
      // caller can match to a real member, and otherwise keep the old floor.
      case PocketOpKind.drop:
      case PocketOpKind.give:
        // All three locations: they can hand over or throw away something
        // they set down five minutes ago ("gives Bob the keys from the
        // nightstand") just as naturally as something in their hands.
        final c = find(p.carrying, op.item);
        final w = c == -1 ? find(p.worn, op.item) : -1;
        final sa = c == -1 && w == -1 ? findAside(op.item) : -1;
        if (c == -1 && w == -1 && sa == -1) break;
        // Take the item as it stands, so its condition travels with it.
        final taken = c != -1
            ? p.carrying.removeAt(c)
            : w != -1
            ? p.worn.removeAt(w)
            : p.setAside.removeAt(sa).item;
        if (op.kind == PocketOpKind.give && op.to.isNotEmpty) {
          onTransfer?.call(op.to, taken);
        }
        receipts.add(
          op.kind == PocketOpKind.give && op.to.isNotEmpty
              ? 'gave ${op.item} to ${op.to}'
              : 'dropped: ${op.item}',
        );
        events?.add(
          PocketEvent(
            kind: op.kind,
            item: taken.name,
            to: op.to,
            where: op.where,
            clothing: w != -1,
          ),
        );

      case PocketOpKind.update:
        if (op.state.isEmpty) break;
        bool touch(List<PocketItem> list) {
          final i = find(list, op.item);
          if (i == -1) return false;
          if (list[i].state != op.state) {
            list[i] = list[i].withState(op.state);
            receipts.add('${op.item}: ${op.state}');
          }
          return true;
        }

        if (touch(p.worn) || touch(p.carrying)) break;
        final u = findAside(op.item);
        if (u == -1 || p.setAside[u].item.state == op.state) break;
        p.setAside[u] = p.setAside[u].withItem(
          p.setAside[u].item.withState(op.state),
        );
        receipts.add('${op.item}: ${op.state}');

      case PocketOpKind.transform:
        // A candy bar becomes a wrapper. The item is REPLACED, not annotated,
        // because what they are holding is genuinely a different thing now.
        if (op.state.isEmpty) break;
        bool morph(List<PocketItem> list) {
          final i = find(list, op.item);
          if (i == -1) return false;
          list[i] = PocketItem.clean(op.state);
          receipts.add('${op.item} → ${op.state}');
          return true;
        }

        if (morph(p.worn) || morph(p.carrying)) break;
        final t = findAside(op.item);
        if (t == -1) break;
        p.setAside[t] = p.setAside[t].withItem(PocketItem.clean(op.state));
        receipts.add('${op.item} → ${op.state}');
    }
  }
  return receipts;
}
