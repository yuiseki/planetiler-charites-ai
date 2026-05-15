# planetiler-charites-ai

A Proof-of-Concept for an AI agent that **co-edits a Planetiler schema and a MapLibre style** from natural-language instructions, with a sub-five-second build cycle for region-scale themes.

The web UI lets you type things like *“parks in green”* or *“thicker roads”*, and a headless `claude -p` agent edits the right schema/style fragments, runs the build, and the map reloads.

## Screenshot

[![Image from Gyazo](https://i.gyazo.com/08c303fe39b4e4bf48bbc6514873131b.jpg)](https://gyazo.com/08c303fe39b4e4bf48bbc6514873131b)

> No hosted demo -- same policy as [charites-ai](https://github.com/yuiseki/charites-ai). The agent runs `claude -p` with `--permission-mode bypassPermissions` and shell access to the repo, which is too much authority to expose on a public URL. Clone and run locally to try it.

## Lineage

- **[charites-ai](https://github.com/yuiseki/charites-ai)** (Dec 2023) -- proved an LLM can author a MapLibre style by splitting it into commented YAML fragments.
- **[planetiler-ai](https://github.com/yuiseki/planetiler-ai)** -- proved an LLM can author a Planetiler schema and serve the tiles.
- **planetiler-charites-ai** (this repo) -- does both together, keeps the two in sync with a build-time contract validator, and feeds the agent through a small FastAPI + SSE pipeline.

## Why the two have to be edited together

With OpenMapTiles the schema is fixed, so the LLM only has to write a style. With a **custom** Planetiler schema the contract (layer ids, `source-layer` names, attribute keys) is invented per theme -- and if schema and style are authored independently, the LLM hallucinates one against the other.

`planetiler-charites-ai`’s answer:

1. **Fragment layout.** Schema and style live in separate fragment files under `themes/{name}/schema/layers/` and `themes/{name}/style/layers/`, with cross-reference metadata in header comments.
2. **Build-time validator.** `scripts/build-style.ts` checks that every `source-layer` in the style exists in the schema, that ids don’t collide, and that the merged MapLibre style passes the official `@maplibre/maplibre-gl-style-spec` validator. Typos fail the build with a precise error the agent can read and fix.
3. **AI agent loop.** `POST /api/instruct` spawns `claude -p` with `--output-format stream-json`, streams the JSON Lines over SSE to the browser, and after the agent finishes `POST /api/build` runs Planetiler and streams its progress to the same UI.

## What’s in the repo

```
planetiler-charites-ai/
├── README.md, LICENSE, CLAUDE.md
├── Makefile                  # one-shot recipes per theme
├── package.json, tsconfig.json
├── api/
│   ├── main.py               # FastAPI: PMTiles static + /api/instruct + /api/build
│   └── requirements.txt
├── web/
│   └── index.html            # MapLibre GL + PMTiles direct read + chat UI
├── themes/
│   ├── monaco/               # original PoC theme -- sea, water, parks, roads, buildings
│   ├── monaco_combined/      # experiment: schema+style co-located per layer (see CLAUDE.md)
│   ├── taito/                # Tokyo Taito-ku -- blank canvas for natural-language demos
│   └── tokyo23/              # all 23 Tokyo special wards -- scale test (~12s end-to-end)
├── scripts/
│   ├── build.ts              # orchestrator
│   ├── build-schema.ts       # merges schema fragments → data/{name}.yml
│   ├── build-style.ts        # charites parser + contract validator + MapLibre validator
│   ├── build-combined.ts     # build for the combined-fragment variant
│   ├── instruct.ts           # standalone CLI agent (skeleton)
│   └── extract-ward-boundary.py  # MLIT N03 → per-ward GeoJSON
├── tile-server/config.json
└── data/sources/
    └── N03-20240101_13.geojson  # MLIT ward polygons (shipped -- CC-BY)
```

## Setup

Prerequisites:

- Node 22+ (for `npx tsx` and the build scripts)
- Python 3.9+ (FastAPI gateway)
- Docker (Planetiler runs as a container)
- `osmium-tool`, `gdal` (for extract / reproject -- `brew install osmium-tool gdal`)
- The `claude` CLI from Anthropic, signed in (for `POST /api/instruct`)

```bash
# 1. install JS deps
npm install

# 2. set up the API venv
python3 -m venv api/.venv
api/.venv/bin/pip install -r api/requirements.txt

# 3. build a theme end-to-end
make monaco            # ~5s on first build (after caches), Monaco
make taito             # downloads ~700MB Kanto PBF on first run, then ~6s
make tokyo23           # ~12s, all 23 special wards (1.79M features)

# 4. serve
api/.venv/bin/uvicorn --app-dir api main:app --port 8002
open "http://localhost:8002/?theme=tokyo23"
```

## Natural-language editing

With the server running, type instructions into the bar at the top of the UI:

- *“Make buildings dark blue”*
- *“Add parks in green”*
- *“Thicker primary roads”*
- *“Use a sea colour for the background”*

The flow:

1. UI → `POST /api/instruct` with `{ instruction, theme }`.
2. FastAPI spawns `claude -p ... --output-format stream-json --permission-mode bypassPermissions --allowedTools "Read Edit Write Bash(make *) ..."`.
3. Claude reads CLAUDE.md + fragment headers, edits the right files, runs `make {theme}-build` (which runs the contract validator + MapLibre validator).
4. UI receives `done` → calls `POST /api/build` → FastAPI runs `make {theme}-pmtiles` and streams Planetiler stdout as SSE.
5. UI reloads the style + PMTiles → the map updates.

## Build pipeline

```
themes/{name}/schema/**.yml   --(scripts/build-schema.ts)-->  data/{name}.yml
themes/{name}/style/style.yml --(@unvt/charites parser)-->   data/{name}.style.yml
                                                              data/{name}.json   ← validated
data/{name}.yml + OSM PBF     --(Planetiler in Docker)-->     data/{name}.pmtiles
```

Build artifacts (`.pmtiles`, `.yml`, `.json`) are produced under `data/` and ignored by git.

## Data sources

- **OSM** -- Geofabrik regional extracts (`make` auto-downloads `kanto-latest.osm.pbf` and the Monaco one).
- **Sea polygons** -- [osmdata.openstreetmap.de](https://osmdata.openstreetmap.de/data/water-polygons.html) simplified water polygons (3857), reprojected to 4326 + clipped to bbox.
- **Tokyo ward polygons** -- MLIT N03 行政区域 2024-01-01 (CC-BY 4.0, shipped under `data/sources/`).

## Status

PoC, but end-to-end working. Known rough edges:

- The contract validator catches `source-layer` typos but **not** schema-side `source` typos yet.
- `monaco_combined/` (co-located fragments) hits structural limits (1:N style layers, global z-order) -- see `CLAUDE.md` for the writeup. The split fragment layout is the recommended default.
- `@unvt/charites` exposes no public JS API, so `scripts/build-style.ts` reaches into `dist/`. A `--format yaml` PR upstream is in scope.

## License

MIT -- see [LICENSE](./LICENSE).
