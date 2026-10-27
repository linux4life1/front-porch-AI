#!/usr/bin/env node
// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Writes the bundled starter worlds: assets/worlds/starter/<id>.fpworld
// (one .fpworld envelope per world, the same shape an exported world with
// locations has) plus index.json, the picker's list. The committed JSON
// files are the artefacts; this script is how they were made, so edit the
// content here and re-run it rather than hand-editing the output:
//
//   node tools/gen_starter_worlds.mjs
//
// Built-in climates travel as `{id, displayName}`: the importer
// (WorldRepository.importWorldJson) keys a built-in by id and stores only
// biomeId, exactly as an exported built-in-climate world imports. The two
// custom climates travel as full Biome snapshots and land in biomeJson.
// test/services/starter_worlds_test.dart checks every file against the
// real decoder, the climate validator and the index counts.

import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'assets', 'worlds', 'starter');

// Cover pictures: covers/<envelope id>.jpg, already sized for a world cover
// (512 px long edge, JPEG, under lib/utils/world_cover.dart's byte cap). They
// ride inline as the envelope's `cover` data URL, the same shape an exported
// world with a picture has. pubspec lists assets/worlds/starter/ without
// recursion, so the JPEGs themselves are not bundled twice.
const COVERS = join(OUT, 'covers');
const COVER_MAX_BYTES = 350 * 1024;

function coverFor(id) {
  const file = join(COVERS, `${id}.jpg`);
  if (!existsSync(file)) throw new Error(`missing cover picture ${file}`);
  const bytes = readFileSync(file);
  if (bytes.length > COVER_MAX_BYTES) throw new Error(`${file} is over ${COVER_MAX_BYTES} bytes`);
  return `data:image/jpeg;base64,${bytes.toString('base64')}`;
}

const BUILT_IN_NAMES = {
  temperate: 'Temperate',
  rainforest: 'Rainforest',
  desert: 'Desert',
  continental: 'Continental',
  tropical: 'Tropical',
  mediterranean: 'Mediterranean',
  highland: 'Highland',
};

const builtIn = (id) => ({ id, displayName: BUILT_IN_NAMES[id] });

// Condition order: clear, cloudy, overcast, fog, rain, storm, snow.
// TempBand declaration index: 0 cold, 1 cool, 2 mild, 3 warm, 4 hot,
// 5 cryogenic, 6 furnace, 7 inferno.
const TUNDRA = {
  id: 'starter_tundra',
  displayName: 'Tundra',
  description: 'Frozen most of the year: snow, fog and grey skies, then a short cool thaw.',
  feel:
    'Breath fogs, boots crunch and every trip outside is planned around the cold. ' +
    'The brief thaw brings meltwater, mud and long pale evenings, never real warmth.',
  weights: {
    winter: [10, 10, 25, 15, 0, 5, 35],
    spring: [12, 15, 25, 18, 5, 3, 22],
    summer: [22, 22, 20, 14, 15, 4, 3],
    autumn: [10, 12, 25, 18, 5, 5, 25],
  },
  baseTemp: { winter: 0, spring: 0, summer: 1, autumn: 0 },
  // Never warmer than cool; no extreme band is reachable, so no °C anchors.
  bandRange: [0, 1],
  diurnalAmplitude: 0.8,
};

const AIRLESS = {
  id: 'starter_airless',
  displayName: 'Airless moon',
  description: 'No air and no rain: a black sky, hard sunlight and the odd drift of dust.',
  feel:
    'Outside is silent and deadly cold; nobody goes out without a suit. ' +
    'Weather means dust kicked up by landers and crawlers, and the long swing from light to dark.',
  weights: {
    winter: [90, 0, 0, 10, 0, 0, 0],
    spring: [88, 0, 0, 12, 0, 0, 0],
    summer: [90, 0, 0, 10, 0, 0, 0],
    autumn: [88, 0, 0, 12, 0, 0, 0],
  },
  // Cryogenic all year and pinned there.
  baseTemp: { winter: 5, spring: 5, summer: 5, autumn: 5 },
  bandRange: [-1, -1],
  displayAnchorsC: { winter: -160, spring: -150, summer: -140, autumn: -150 },
  diurnalAmplitude: 3.0,
  conditionSkin: {
    clear: {
      label: 'Black sky',
      emoji: '🌑',
      stance: 'deadly',
      flavour: 'No air outside the walls: suits and airlocks or nothing.',
    },
    fog: {
      label: 'Dust drift',
      emoji: '🌫️',
      stance: 'dangerous',
      flavour: 'Fine grey dust hangs low over the plain and clings to every seal.',
    },
  },
};

const lore = (name, keys, content) => ({ name, keys, content });

/** One .fpworld envelope (fp_world_package.dart encodeFpWorld shape). */
function place({ id, name, description, climate = null, traits = null, entries = [], locations = [], defaultPlaceId = null }) {
  const env = {
    formatVersion: 1,
    id,
    name,
    description,
    cover: coverFor(id),
    lorebook: { entries },
    climate_enabled: climate !== null,
  };
  if (climate !== null) env.biome = climate;
  if (climate !== null && traits) env.place_traits = traits;
  if (locations.length) env.locations = locations;
  // Where chats that get the world start: every world names one. The
  // importer re-points it at the imported copy of that place.
  if (defaultPlaceId) env.default_place_id = defaultPlaceId;
  env.meta = { sourceId: id };
  return env;
}

const WORLDS = [
  {
    key: 'whitereach',
    blurb: 'A frozen tundra with three warm valley towns, each with a gentle climate of its own.',
    root: {
      name: 'The Whitereach',
      climate: TUNDRA,
      description:
        'A wide white country of frozen lakes, low hills and long wind, where snow lies on the ground most of the year and fog rolls in off the ice without warning. ' +
        'Sled runners hiss along marked trails between the warm valleys, and travellers learn to read the sky before they leave a door. ' +
        'Lamps burn in the windows all day through the dark months.',
    },
    places: [
      {
        slug: 'hearthford',
        name: 'Hearthford',
        climate: builtIn('temperate'),
        description:
          'A valley town tucked into a fold of the hills, where warm ground keeps the snow off the fields while the ridges above stay white. ' +
          'Steam drifts from vents beside the lanes, the market stays open late, and children play outside in shirtsleeves while frost glitters on the peaks.',
      },
      {
        slug: 'thawwater-springs',
        name: 'Thawwater Springs',
        climate: builtIn('mediterranean'),
        description:
          'Terraced hot-spring pools climb a hillside under a great glass roof, beaded with condensation and ringed with potted lemon trees. ' +
          'Bathers lounge in the steam, attendants carry towels and iced tea between the tiers, and through the glass the snowfields shine blue at dusk.',
      },
      {
        slug: 'emberlight',
        name: 'Emberlight',
        climate: builtIn('continental'),
        description:
          'A mining town built over its own warm vents: brick chimneys, copper pipes and lit workshop windows. ' +
          'Shift whistles mark the day and the streets smell of coal smoke and fresh bread. ' +
          'Winters still bring real snow, but the town gets proper summers too, loud with thunderstorms, which is more than the ice outside can say.',
      },
    ],
  },
  {
    key: 'kestrel-reach',
    blurb: 'An airless, low-gravity moon with a farming dome, a spinning ring and a suited outpost.',
    root: {
      name: 'Kestrel Reach',
      climate: AIRLESS,
      traits: { atmosphere: 'unbreathable', gravity: 'low' },
      description:
        'A grey, airless moon under a black sky, where the sun is a hard white disc and a banded giant planet fills a quarter of the horizon. ' +
        'Nothing makes a sound outside, footprints last for years in the fine dust, and everyone moves in long, slow bounds. ' +
        'Settlements huddle under domes and in buried halls, linked by pressurised crawlers.',
    },
    places: [
      {
        slug: 'dome-town-meridian',
        name: 'Dome Town Meridian',
        climate: builtIn('temperate'),
        traits: { gravity: 'low' },
        description:
          'A farming town under a vast clear dome, with terraced fields, orchards and a small lake the colonists swear is the bluest water on the moon. ' +
          'People bounce when they walk, children clear fences for fun, and the dome rolls out rain on a schedule everyone grumbles about. ' +
          'Beyond the glass the grey plain runs to a black horizon.',
      },
      {
        slug: 'the-ring',
        name: 'The Ring',
        climate: builtIn('mediterranean'),
        description:
          'An orbital habitat shaped like a great wheel, spun so its people walk with a familiar weight. ' +
          'Its inner surface curves up into the sky in both directions: parks, canals and terraced neighbourhoods under a long sunlit strip that dims each evening. ' +
          'It feels like a warm coastal town, if you ignore the houses hanging overhead.',
      },
      {
        slug: 'outpost-nine',
        name: 'Outpost Nine',
        description:
          'A cramped research and mining outpost dug into a crater wall, reached by crawler across the open plain. ' +
          'Nobody steps outside without a pressure suit, and every door to the surface is an airlock with a cycle light and a checklist. ' +
          'Inside it smells of machine oil and recycled air, and the crew keep a card game running in the galley.',
      },
    ],
  },
  {
    key: 'verdance-basin',
    blurb: 'Rainforest river country: stilt houses, a treetop market and a quiet logging village.',
    root: {
      name: 'Verdance Basin',
      climate: builtIn('rainforest'),
      description:
        'A vast river basin roofed by rainforest, where the air is thick and green and it rains a little nearly every day. ' +
        'Brown rivers wind between the trees, birds and frogs call all night, and people travel by boat or rope bridge because the ground floods half the year.',
    },
    places: [
      {
        slug: 'stiltwater',
        name: 'Stiltwater',
        description:
          'A town of houses on tall stilts above the floodplain, joined by plank walkways and ladders. ' +
          'When the river rises, people fish from their porches and children paddle canoes between the homes; when it falls, gardens appear in the mud below.',
      },
      {
        slug: 'canopy-market',
        name: 'Canopy Market',
        description:
          'Trade platforms lashed high in the branches of giant trees, reached by rope lifts and swaying bridges. ' +
          'Traders sell fruit, dyes, carved wood and gossip under oilcloth awnings, and rain drips through the leaves onto everyone’s bargains.',
      },
      {
        slug: 'fern-hollow',
        name: 'Fern Hollow',
        description:
          'A logging village gone quiet since the mill closed, its sawdust heaps grown over with ferns and moss. ' +
          'A handful of families stay on, keeping bees and running a little inn, and the forest creeps a little further into the streets each wet season.',
      },
    ],
  },
  {
    key: 'monsoon-coast',
    blurb: 'A hot, stormy coast of fishing towns, rice terraces and an old lantern-lit port.',
    root: {
      name: 'Monsoon Coast',
      climate: builtIn('tropical'),
      description:
        'A long, hot coastline of palm groves, river deltas and fishing towns, where the year turns on the monsoon. ' +
        'Mornings are bright and sticky, afternoon storms roll in off the sea like clockwork, and evenings smell of wet earth, grilled fish and woodsmoke.',
    },
    places: [
      {
        slug: 'palmreach',
        name: 'Palmreach',
        description:
          'A fishing town on a narrow sandbar between a calm lagoon and the open sea. ' +
          'Boats are hauled up the beach each evening, nets dry on poles, and the whole town turns out when the catch comes in. ' +
          'Storm warnings travel by bell from the watchtower at the point.',
      },
      {
        slug: 'reedbank',
        name: 'Reedbank',
        description:
          'A river town of rice terraces stepping down to a wide brown river, with a flat ferry that crosses on a cable. ' +
          'Farmers work the paddies in wide hats, water buffalo wallow in the shallows, and the ferry keeper knows everybody’s business by noon.',
      },
      {
        slug: 'old-lantern-quay',
        name: 'Old Lantern Quay',
        description:
          'A half-abandoned port where the big ships stopped calling years ago. ' +
          'Warehouses stand empty with their doors hanging open, but a few lantern-lit tea stalls and a night market still wake the waterfront after dark, and old sailors trade stories on the bollards.',
      },
    ],
  },
  {
    key: 'harborside',
    blurb: 'A small seaside town with a working quay, a lantern market and a lighthouse.',
    root: {
      name: 'Harborside',
      climate: builtIn('temperate'),
      description:
        'A small seaside town of slate roofs and painted doors climbing a hill above a working harbour. ' +
        'Gulls wheel over the fishing boats, the weather changes three times before lunch, and everybody has an opinion about the best bench for watching the sunset.',
    },
    places: [
      {
        slug: 'the-quay',
        name: 'The Quay',
        description:
          'The working waterfront, crowded with crab pots, coiled rope and boats being scraped and painted. ' +
          'Crews mend nets on the stones, the harbourmaster’s radio crackles from an open window, and the smell of salt and diesel hangs over everything.',
      },
      {
        slug: 'lantern-street-market',
        name: 'Lantern Street Market',
        description:
          'A narrow cobbled street of shops and stalls strung with lanterns, busiest on weekend evenings. ' +
          'Bakers, booksellers and a stall selling hot chips in paper cones compete for the crowds, and buskers play in the doorway of the old chapel.',
      },
      {
        slug: 'lighthouse-point',
        name: 'Lighthouse Point',
        description:
          'A grassy headland at the end of the harbour wall, crowned by a white lighthouse that still turns every night. ' +
          'Wind flattens the grass, waves boom against the rocks below, and on clear evenings the lights of the next town glimmer along the coast.',
      },
    ],
  },
  {
    key: 'long-road',
    blurb: 'A road across the plains that climbs into the hills and dips into dry country.',
    root: {
      name: 'The Long Road',
      climate: builtIn('continental'),
      description:
        'A long road across open plains, river country and hills, travelled by carters, drifters and families moving on. ' +
        'Winters bury it in snow and summers bring heat and thunder, so the inns along the way fill up whenever the sky turns.',
    },
    places: [
      {
        slug: 'dustwell-crossing',
        name: 'Dustwell Crossing',
        climate: builtIn('desert'),
        description:
          'A dusty crossroads town around a deep stone well, where the road dips south into dry country. ' +
          'Sun-bleached signs creak in the wind, the general store sells water by the jug, and travellers wait out the midday heat on the shaded porch of the only tavern.',
      },
      {
        slug: 'pinecrest-pass',
        name: 'Pinecrest Pass',
        climate: builtIn('highland'),
        description:
          'A high mountain pass where the road climbs through pine forest to a stone waystation at the top. ' +
          'Snow lingers late into spring, fog pours over the ridge without warning, and the keepers ring a bell to guide travellers in when the cloud comes down.',
      },
      {
        slug: 'ferry-landing',
        name: 'Ferry Landing',
        description:
          'A river landing where the road meets a wide, slow river and a rope ferry carries carts across. ' +
          'There is a boathouse, a tea stall and a noticeboard thick with messages left for travellers, and in a storm the ferry ties up and everyone waits it out together under the eaves.',
      },
    ],
  },
  {
    key: 'greenhollow',
    blurb: 'A country estate with house lore, and rooms that add lore of their own.',
    root: {
      name: 'Greenhollow Estate',
      climate: builtIn('mediterranean'),
      description:
        'A rambling country estate of honey-coloured stone among olive groves, vineyards and old gardens. ' +
        'Summers are bright and dry, with cicadas in the cypresses; winters are mild and rainy, and the house smells of woodsmoke and baking. ' +
        'The family, their staff and their guests share one long table at supper.',
      entries: [
        lore('The Greenhollow family', ['Greenhollow family', 'the family', 'household'],
          'The Greenhollow family has kept the estate for five generations. They are a quiet, bookish household: the elders keep the accounts and the orchard, and the younger ones come home every harvest. Guests are treated as family once they have eaten at the long table.'),
        lore('The gardener', ['gardener', 'gardens', 'hedges', 'roses'],
          'The gardener has worked the grounds longer than anyone can remember. Weathered, unhurried and kind, they talk more to the roses than to people, know every path on the estate, and keep a spare key to almost everything.'),
        lore('The locked library', ['library', 'locked door', 'east wing'],
          'The library in the east wing has been locked for years. The family says only that it is resting. Lamplight is sometimes seen under the door late at night, and its key is not on the housekeeper’s ring.'),
        lore('House rule: the long table', ['supper', 'dinner', 'long table', 'meal'],
          'Supper is taken together at the long table at sundown. Nobody at Greenhollow eats alone, and nobody talks business at the table.'),
        lore('House rule: the hall bell', ['bell', 'curfew', 'ten o’clock', 'late at night'],
          'When the hall bell rings at ten, the lamps go out in the shared rooms and voices drop. The house is old and sound carries, so after the bell people move softly.'),
        lore('The Orchard Fair', ['harvest', 'festival', 'Orchard Fair', 'cider'],
          'Every autumn the estate opens its gates for the Orchard Fair: apple picking, a cider press in the yard, music on the lawn and a lantern walk through the trees. Neighbours come from miles around.'),
      ],
    },
    places: [
      {
        slug: 'the-conservatory',
        name: 'The Conservatory',
        description:
          'A tall glasshouse of white iron and old glass on the south side of the house, full of palms, orchids and climbing vines. ' +
          'Rain drums on the roof in winter, summer sun turns it into a hothouse, and wicker chairs hide among the leaves for quiet conversations.',
        entries: [
          lore('The night-blooming vine', ['vine', 'bloom', 'flowers', 'scent'],
            'A pale vine in the conservatory flowers only after dark, filling the glasshouse with a scent like honey and rain. The family likes to hold late conversations under it.'),
          lore('The conservatory stove', ['stove', 'heat', 'warm'],
            'An iron stove keeps the glasshouse warm through the winter. The gardener banks it every night and does not like anyone else touching it.'),
        ],
      },
      {
        slug: 'the-kitchens',
        name: 'The Kitchens',
        description:
          'Big flagstoned kitchens below the house, with a bread oven, copper pans and a scrubbed table long enough to seat twenty. ' +
          'Something is always simmering, a radio plays softly by the window, and anyone who sits down is handed a knife and some vegetables.',
        entries: [
          lore('The bread oven', ['bread', 'oven', 'baking', 'loaves'],
            'The old brick bread oven is fired before dawn. The first loaves go to the long table and the heels go to whoever is up early enough to ask.'),
          lore('Kitchen rule', ['kitchen rule', 'apron', 'cook'],
            'Anyone who sits at the kitchen table helps: peeling, stirring, or at least drying. The cook says idle hands spoil the soup.'),
        ],
      },
      {
        slug: 'the-old-orchard',
        name: 'The Old Orchard',
        description:
          'Rows of gnarled apple, pear and plum trees running down the slope behind the house to a stream. ' +
          'Bees work the blossom in spring, the grass grows long and gold in summer, and in autumn the ladders come out and the whole household picks.',
        entries: [
          lore('The crooked tree', ['crooked tree', 'oldest tree', 'swing'],
            'A crooked apple tree at the heart of the orchard is older than the house. A rope swing hangs from its lowest branch, and generations of the family have carved their initials in its bark.'),
        ],
      },
    ],
  },
];

mkdirSync(OUT, { recursive: true });
const index = [];
for (const w of WORLDS) {
  const rootId = `starter-${w.key}`;
  const envelope = place({
    id: rootId,
    name: w.root.name,
    description: w.root.description,
    climate: w.root.climate,
    traits: w.root.traits,
    entries: w.root.entries ?? [],
    // A world may name its start (`start: <slug>`); else its first place.
    defaultPlaceId: `${rootId}-${w.start ?? w.places[0].slug}`,
    locations: w.places.map((p) =>
      place({
        id: `${rootId}-${p.slug}`,
        name: p.name,
        description: p.description,
        climate: p.climate ?? null,
        traits: p.traits,
        entries: p.entries ?? [],
      }),
    ),
  });
  writeFileSync(join(OUT, `${w.key}.fpworld`), `${JSON.stringify(envelope, null, 2)}\n`);
  const loreEntries = (w.root.entries ?? []).length + w.places.reduce((n, p) => n + (p.entries ?? []).length, 0);
  index.push({
    id: w.key,
    name: w.root.name,
    blurb: w.blurb,
    climate: w.root.climate.displayName,
    customClimate: !(w.root.climate.id in BUILT_IN_NAMES),
    places: w.places.length,
    ownClimates: w.places.filter((p) => p.climate).length,
    loreEntries,
  });
}
writeFileSync(join(OUT, 'index.json'), `${JSON.stringify({ formatVersion: 1, worlds: index }, null, 2)}\n`);
console.log(`wrote ${index.length} starter worlds to ${OUT}`);
