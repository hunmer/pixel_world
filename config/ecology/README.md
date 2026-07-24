# Modular ecology configuration

`manifest.json` is the only entry point. Its module order is stable and is part
of deterministic world generation; add new files to the manifest instead of
merging them into an existing catalog.

## Responsibilities

- `world/`: shared height, region, noise, flora-layer, and terrain-material defaults.
- `species/`: what an individual plant, animal, or ambient effect is; resources,
  animation, traits, and behavior components live here.
- `communities/`: reusable spatial compositions such as `pond_lilies`,
  `wolf_pack`, or a future volcanic fumarole patch.
- `biomes/`: terrain classifier/generator modules and the communities attached
  to their biome or habitat tags.

Runtime composition is:

```text
manifest -> EcologyRegistry
         -> TerrainSampler -> CellContext (biome + habitat tags + surface)
         -> EcologyResolver -> additive CommunityDefinitions
         -> CellState -> renderer / navigation / fauna
```

The renderer only consumes `CellState`. Placement and movement must use context,
traits, and occupancy tags rather than texture names or render priority.

## Adding a biome

1. Add a script extending `scripts/world/biomes/biome_module.gd`.
2. Add one biome JSON module and register it in `manifest.json`.
3. Declare module-local noise fields in `noise_fields`.
4. Return a stable `surface_id` from the module and declare its textures under
   that biome's `generation.materials`.
5. Add species/community modules and attach their IDs to the biome.

Minimal shape:

```json
{
  "version": 1,
  "kind": "biomes",
  "biomes": [{
    "id": "volcanic",
    "script": "res://scripts/world/biomes/volcanic_biome.gd",
    "priority": 400,
    "noise_fields": {
      "volcanic_heat": {"seed_offset": 1401, "frequency": 0.006}
    },
    "profile": {"heat_noise_field": "volcanic_heat"},
    "generation": {
      "materials": {
        "surfaces": {
          "basalt": {
            "top_texture": "res://meowa_tiles/terrain/basalt.png",
            "column_texture": "reuse_top",
            "minimap_color": [0.16, 0.12, 0.13, 1.0],
            "tags": ["rocky", "igneous"]
          }
        }
      }
    },
    "tags": ["volcanic", "hot"],
    "attachments": [
      {"community_id": "volcanic_fumaroles", "weight": 1.0}
    ]
  }]
}
```

No biome ID, noise ID, surface ID, minimap color, or weather tag should be added
to `main.gd`. A new algorithm belongs in a biome module; reusable spatial
composition belongs in a community.

## Adding a community

1. Define each member in the matching `species/` catalog.
2. Add one reusable definition under `communities/`, including its habitat,
   distribution, member weights, and optional fixed members.
3. Attach the community to one or more biome modules. The attachment is
   additive, so the same pond, pack, or decoration cluster can be reused by
   several biomes without copying placement code.
4. Keep rendering and movement behavior behind their registries. A community
   ID or species ID must not create a new branch in `main.gd`.

New flora and fauna communities automatically use `CommunitySpawner` and
`MemberComposer`. They can therefore express patches, solitary animals,
families, homogeneous schools, and mixed packs entirely in data.
`distribution.single_species` chooses one weighted fill species for an entire
group, while `anchor_search_radius` lets narrow habitats such as rivers select
the nearest valid cell without turning placement back into per-cell scatter.
Completed and empty territory plans share the bounded community state cache, so
one-cell streaming updates never repeat the same habitat search on the input
thread.
Aquatic species opt into `allowed_surfaces: ["water"]`; their communities still
declare explicit water-depth, climate, landform, population, and spacing rules.
Short-lived wildlife can instead use an ambient renderer. The bird renderer is
one such module: ecology only chooses sparse temperate ground candidates, while
the renderer owns walking, proximity take-off, viewport-lifetime flyovers, and
cleanup through the optional observer update supplied by `AmbientRegistry`.
Existing tuned communities carry
`metadata.legacy_placement_seed`; this selects a compatibility adapter only so
their established density and deterministic layout do not change. Do not add
that field to new content.

For example, an icefield can attach sparse conifer patches, seal colonies, and
aurora ambience, while a volcanic biome can attach fumarole patches and mixed
lava-fauna groups. Neither requires editing the terrain sampler, renderer, or
main scene.

## Determinism and compatibility

- IDs, `stream_key`, and legacy `placement_seed` values are save/world contracts.
- File paths and translated display names must never be random seeds.
- Existing streams keep their legacy numeric salt; new modules use a unique,
  namespaced stream such as `volcanic/fumaroles/member`.
- Reordering manifest entries or changing a stable ID requires an explicit world
  version migration.
- `legacy_bundles.json` exists only while old first-match ecology is being
  migrated. New content must use additive biome attachments and communities.
