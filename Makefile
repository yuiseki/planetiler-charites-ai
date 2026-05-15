# planetiler-charites-ai Makefile

MEMORY_OPTIONS = --memory 4g --memory-swap -1
JAVA_TOOL_OPTIONS = -Xms2g -Xmx2g

pwd = $(shell pwd)

DOCKER_RUN = docker run --rm \
    -u `id -u`:`id -g` \
    $(MEMORY_OPTIONS) \
    -e JAVA_TOOL_OPTIONS="$(JAVA_TOOL_OPTIONS)" \
    -v "$(pwd)/data":/data \
    ghcr.io/onthegomap/planetiler:latest

MONACO_PBF_URL = https://download.geofabrik.de/europe/monaco-latest.osm.pbf
# Geofabrik Kanto region (Tokyo + neighbouring prefectures, ~700MB). Used as
# the source for Tokyo themes so third parties can reproduce without any
# in-house tooling.
KANTO_PBF_URL = https://download.geofabrik.de/asia/japan/kanto-latest.osm.pbf
KANTO_PBF = data/sources/kanto-latest.osm.pbf
N03_GEOJSON = data/sources/N03-20240101_13.geojson
# osmdata.openstreetmap.de simplified water polygons (only 3857 is published
# in simplified form; we reproject to 4326 ourselves).
WATER_POLYGONS_URL = https://osmdata.openstreetmap.de/download/simplified-water-polygons-split-3857.zip
WATER_POLYGONS_ZIP = data/sources/simplified-water-polygons-split-3857.zip
WATER_POLYGONS_SHP = /vsizip/$(WATER_POLYGONS_ZIP)/simplified-water-polygons-split-3857/simplified_water_polygons.shp
MONACO_BBOX = 7.3 43.4 7.7 43.8

.PHONY: all
all:
	@echo "Available targets:"
	@echo "  monaco-data    Download Monaco OSM PBF (~2 MB)"
	@echo "  monaco-build   Merge schema + style fragments to data/"
	@echo "  monaco-tiles   Generate data/monaco.mbtiles with Planetiler"
	@echo "  monaco         All of the above, in order"

.PHONY: install
install:
	npm install

# ---- Monaco theme --------------------------------------------------------

.PHONY: monaco-data
monaco-data:
	@mkdir -p data
	@if [ ! -f data/monaco-latest.osm.pbf ]; then \
		echo "Downloading Monaco PBF..."; \
		curl -L -o data/monaco-latest.osm.pbf $(MONACO_PBF_URL); \
	else \
		echo "data/monaco-latest.osm.pbf already exists. Skipping download."; \
	fi

.PHONY: monaco-coastline
monaco-coastline:
	@mkdir -p data/sources
	@if [ ! -f $(WATER_POLYGONS_ZIP) ]; then \
		echo "Downloading simplified water polygons (~50 MB, one-time)..."; \
		curl -L -o $(WATER_POLYGONS_ZIP) $(WATER_POLYGONS_URL); \
	else \
		echo "Water polygons zip already cached."; \
	fi
	@if [ ! -f data/monaco_sea.geojson ]; then \
		echo "Reproject (EPSG:3857 -> 4326) + clip to Monaco bbox..."; \
		ogr2ogr -f GeoJSON -lco RFC7946=YES \
			-t_srs EPSG:4326 \
			-clipdst $(MONACO_BBOX) \
			data/monaco_sea.geojson \
			$(WATER_POLYGONS_SHP); \
		echo "Generated data/monaco_sea.geojson ($$(wc -c < data/monaco_sea.geojson) bytes)"; \
	else \
		echo "data/monaco_sea.geojson already exists. Skipping clip."; \
	fi

.PHONY: monaco-build
monaco-build:
	npx tsx scripts/build.ts monaco

.PHONY: monaco-tiles
monaco-tiles:
	$(DOCKER_RUN) generate-custom \
		--schema=/data/monaco.yml \
		--output=/data/monaco.mbtiles \
		--bounds=7.3,43.4,7.7,43.8 \
		--download \
		--force

.PHONY: monaco-pmtiles
monaco-pmtiles:
	$(DOCKER_RUN) generate-custom \
		--schema=/data/monaco.yml \
		--output=/data/monaco.pmtiles \
		--bounds=7.3,43.4,7.7,43.8 \
		--download \
		--force

.PHONY: monaco
monaco: monaco-data monaco-coastline monaco-build monaco-tiles
	@echo "Monaco theme built."
	@echo "Next: docker compose up -d  &&  open http://localhost:8000/styles/monaco/"

# ---- Cleanup -------------------------------------------------------------

# ---- Shared: Kanto PBF + N03 ward polygons ------------------------------

.PHONY: kanto-pbf
kanto-pbf:
	@mkdir -p data/sources
	@if [ ! -f $(KANTO_PBF) ]; then \
		echo "Downloading Geofabrik Kanto PBF (~700MB, one-time)..."; \
		curl -L -o $(KANTO_PBF) $(KANTO_PBF_URL); \
	else \
		echo "$(KANTO_PBF) already cached."; \
	fi

# ---- Taito theme (Tokyo inland, blank canvas for natural-language demo) -

TAITO_BBOX_CSV = 139.76,35.69,139.81,35.74

.PHONY: taito-data
taito-data: kanto-pbf
	@if [ ! -f data/taito-latest.osm.pbf ]; then \
		echo "Extracting Taito bbox from Kanto PBF..."; \
		osmium extract -b $(TAITO_BBOX_CSV) \
			$(KANTO_PBF) \
			-o data/taito-latest.osm.pbf --overwrite; \
	else \
		echo "data/taito-latest.osm.pbf already exists."; \
	fi

.PHONY: taito-boundary
taito-boundary:
	@if [ ! -f data/taito_boundary.geojson ]; then \
		echo "Extracting Taito-ku polygon from N03..."; \
		python3 scripts/extract-ward-boundary.py taito \
			$(N03_GEOJSON) data/taito_boundary.geojson; \
	fi

.PHONY: taito-build
taito-build: taito-boundary
	npx tsx scripts/build.ts taito

.PHONY: taito-pmtiles
taito-pmtiles:
	$(DOCKER_RUN) generate-custom \
		--schema=/data/taito.yml \
		--output=/data/taito.pmtiles \
		--bounds=$(TAITO_BBOX_CSV) \
		--force

.PHONY: taito
taito: taito-data taito-boundary taito-build taito-pmtiles
	@echo "Taito theme built."

# ---- Tokyo 23 wards (scale test) ---------------------------------------

TOKYO23_BBOX_CSV = 139.55,35.52,139.93,35.82

.PHONY: tokyo23-data
tokyo23-data: kanto-pbf
	@if [ ! -f data/tokyo23-latest.osm.pbf ]; then \
		echo "Extracting Tokyo 23 wards bbox from Kanto PBF..."; \
		osmium extract -b $(TOKYO23_BBOX_CSV) \
			$(KANTO_PBF) \
			-o data/tokyo23-latest.osm.pbf --overwrite; \
	fi

.PHONY: tokyo23-boundary
tokyo23-boundary:
	@if [ ! -f data/tokyo23_boundary.geojson ]; then \
		echo "Extracting 23 ward polygons from N03..."; \
		python3 scripts/extract-ward-boundary.py tokyo23 \
			$(N03_GEOJSON) data/tokyo23_boundary.geojson; \
	fi

.PHONY: tokyo23-build
tokyo23-build: tokyo23-boundary
	npx tsx scripts/build.ts tokyo23

.PHONY: tokyo23-pmtiles
tokyo23-pmtiles:
	$(DOCKER_RUN) generate-custom \
		--schema=/data/tokyo23.yml \
		--output=/data/tokyo23.pmtiles \
		--bounds=$(TOKYO23_BBOX_CSV) \
		--force

.PHONY: tokyo23
tokyo23: tokyo23-data tokyo23-build tokyo23-pmtiles

# ---- Monaco combined theme (schema+style co-located experiment) ---------

.PHONY: monaco_combined-build
monaco_combined-build:
	npx tsx scripts/build-combined.ts monaco_combined

.PHONY: monaco_combined-tiles
monaco_combined-tiles:
	$(DOCKER_RUN) generate-custom \
		--schema=/data/monaco_combined.yml \
		--output=/data/monaco_combined.mbtiles \
		--bounds=7.3,43.4,7.7,43.8 \
		--download \
		--force

.PHONY: monaco_combined
monaco_combined: monaco-data monaco_combined-build monaco_combined-tiles
	@echo "Monaco combined theme built."

# ---- Cleanup -------------------------------------------------------------

.PHONY: clean
clean:
	rm -f data/monaco.yml data/monaco.style.yml data/monaco.json data/monaco.mbtiles
	rm -f data/monaco_combined.yml data/monaco_combined.style.yml data/monaco_combined.json data/monaco_combined.mbtiles
