# Instructions for AI agents

This project co-generates a Planetiler **schema** and a MapLibre **style** from natural language. The agent MUST keep the two in sync.

## Hard rules

1. **Never edit `data/*.yml` or `data/*.json` by hand.** They are build artifacts produced by `scripts/build.ts`. Edit fragments under `themes/{name}/schema/` and `themes/{name}/style/`, then run `make {name}-build`.
2. **Every fragment file has a header comment.** Do not delete the header. The agent reads it to find pairs.
3. **Editing a schema layer ALWAYS implies inspecting the style layer that references it**, and vice versa. If you rename a `layer_id` in the schema, rename the matching `source-layer` in the style in the same change.

## Fragment header format

### Schema fragment (`themes/{name}/schema/layers/*.yml`)

```yaml
# !planetiler-charites-ai schema-layer
# Layer ID: <id used as Planetiler layer id AND MapLibre source-layer>
# Geometry: point | line | polygon
# Sources: osm | natural_earth | ...
# Attributes:
#   - <key>: <one-line description>
# Style consumers:
#   - style/layers/<file>.yml
# Instructions (few-word phrases, used for example selection):
#   - <phrase>
```

### Style fragment (`themes/{name}/style/layers/*.yml`)

```yaml
# !planetiler-charites-ai style-layer
# File name of this style:
#   - <basename>.yml
# Schema layer: <layer id in the matching schema fragment>
# Reads attributes:
#   - <key>
# Instructions (few-word phrases):
#   - <phrase>
```

## Build pipeline

```
themes/{name}/schema/**.yml   --(scripts/build-schema.ts)-->  data/{name}.yml
themes/{name}/style/style.yml --(charites build)------------> data/{name}.json
data/{name}.yml + planet PBF  --(planetiler)----------------> data/{name}.pmtiles
```

`make {name}` runs the whole pipeline.

## After editing fragments -- MUST run `make {name}-build`

When you edit any fragment under `themes/{name}/`, you MUST run:

```bash
make {name}-build
```

This regenerates `data/{name}.yml` and `data/{name}.json` and -- crucially --
runs the contract validator and the MapLibre style spec validator. If you
broke the schema↔style binding (typo in `source-layer`, missing layer id,
duplicate ids) OR wrote an invalid MapLibre style expression (e.g. a
literal array inside `match`), the build will fail with a precise error.
Fix and retry rather than committing a broken state.

## DO NOT run `make {name}-pmtiles` yourself

The web UI runs `make {name}-pmtiles` after your edits succeed, so it can
stream the Planetiler progress to the user. If you also run it, the user
sees no progress for a long second build.

In summary: edit fragments, run `make {name}-build`, stop.

## Adding a new theme

1. Copy `themes/monaco/` to `themes/{name}/`.
2. Edit `themes/{name}/schema/_meta.yml` (schema_name).
3. Add a target to `Makefile` (the `define theme_targets` macro covers the common case).
4. `make {name}-build && make {name}-tiles`.
