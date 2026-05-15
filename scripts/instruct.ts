/**
 * LLM agent skeleton -- co-edits a schema fragment AND its paired style fragment
 * in a single natural-language turn.
 *
 *   npm run instruct -- monaco "Make buildings dark blue and extrude at z16+"
 *
 * Current state: fragment loading + cross-reference resolution are wired up,
 * but the actual LLM call is a TODO. This file is here to lock the data shape
 * the agent will operate on, so the schema/style fragments and the build
 * scripts can be validated end-to-end first.
 */
import fs from "node:fs/promises";
import path from "node:path";
import process from "node:process";

type SchemaFragment = {
  filePath: string;
  layerId: string;
  geometry?: string;
  sources: string[];
  attributes: string[];
  styleConsumers: string[];
  instructions: string[];
  body: string;
};

type StyleFragment = {
  filePath: string;
  fileName: string;
  schemaLayer: string | null;
  readsAttributes: string[];
  instructions: string[];
  body: string;
};

const HEADER_TAG_SCHEMA = "# !planetiler-charites-ai schema-layer";
const HEADER_TAG_STYLE = "# !planetiler-charites-ai style-layer";

const parseHeader = (text: string): Record<string, string[]> => {
  const headerLines: string[] = [];
  for (const line of text.split("\n")) {
    if (line.startsWith("#")) headerLines.push(line);
    else break;
  }
  const out: Record<string, string[]> = {};
  let currentKey: string | null = null;
  for (const raw of headerLines) {
    const line = raw.replace(/^#\s?/, "");
    const m = line.match(/^([A-Z][A-Za-z ]+):\s*(.*)$/);
    if (m) {
      currentKey = m[1].trim();
      const inline = m[2].trim();
      out[currentKey] = inline ? [inline] : [];
    } else if (currentKey && line.trim().startsWith("- ")) {
      out[currentKey].push(line.trim().replace(/^- /, ""));
    }
  }
  return out;
};

const loadSchemaFragments = async (
  themeName: string,
): Promise<SchemaFragment[]> => {
  const dir = path.resolve("themes", themeName, "schema", "layers");
  const files = await fs.readdir(dir);
  const out: SchemaFragment[] = [];
  for (const f of files) {
    if (!f.endsWith(".yml") && !f.endsWith(".yaml")) continue;
    const fullPath = path.join(dir, f);
    const text = await fs.readFile(fullPath, "utf-8");
    if (!text.startsWith(HEADER_TAG_SCHEMA)) continue;
    const h = parseHeader(text);
    out.push({
      filePath: fullPath,
      layerId: (h["Layer ID"] ?? [""])[0],
      geometry: (h["Geometry"] ?? [])[0],
      sources: (h["Sources"] ?? [])[0]?.split(",").map((s) => s.trim()) ?? [],
      attributes: h["Attributes"] ?? [],
      styleConsumers: h["Style consumers"] ?? [],
      instructions: h["Instructions"] ?? [],
      body: text,
    });
  }
  return out;
};

const loadStyleFragments = async (
  themeName: string,
): Promise<StyleFragment[]> => {
  const dir = path.resolve("themes", themeName, "style", "layers");
  const files = await fs.readdir(dir);
  const out: StyleFragment[] = [];
  for (const f of files) {
    if (!f.endsWith(".yml") && !f.endsWith(".yaml")) continue;
    const fullPath = path.join(dir, f);
    const text = await fs.readFile(fullPath, "utf-8");
    if (!text.startsWith(HEADER_TAG_STYLE)) continue;
    const h = parseHeader(text);
    out.push({
      filePath: fullPath,
      fileName: (h["File name of this style"] ?? [f])[0],
      schemaLayer: ((h["Schema layer"] ?? [])[0] || "").replace(
        /\s*\(none.*\)\s*/,
        "",
      ) || null,
      readsAttributes: h["Reads attributes"] ?? [],
      instructions: h["Instructions"] ?? [],
      body: text,
    });
  }
  return out;
};

const main = async () => {
  const themeName = process.argv[2];
  const instruction = process.argv.slice(3).join(" ");
  if (!themeName || !instruction) {
    console.error('Usage: instruct.ts <theme-name> "<instruction>"');
    process.exit(1);
  }

  const schemaFragments = await loadSchemaFragments(themeName);
  const styleFragments = await loadStyleFragments(themeName);

  // Cross-reference index: schema layer id -> style fragments that consume it.
  const pairs = schemaFragments.map((s) => ({
    schema: s,
    styles: styleFragments.filter((st) => st.schemaLayer === s.layerId),
  }));

  console.log("== Theme:", themeName);
  console.log("== Instruction:", instruction);
  console.log("== Schema/Style pairs:");
  for (const p of pairs) {
    console.log(
      `  - schema layer "${p.schema.layerId}" (${p.schema.filePath})`,
    );
    for (const st of p.styles) {
      console.log(`      <-> style ${st.fileName} (${st.filePath})`);
    }
  }

  // TODO: LLM call.
  // 1. Few-shot example selection over `instructions` of each fragment pair
  //    (mirrors charites-ai's SemanticSimilarityExampleSelector).
  // 2. Prompt the model with the SELECTED schema fragment AND its paired
  //    style fragment(s). Ask for both files back in one response, so attribute
  //    names stay consistent.
  // 3. Write back to disk, then `npx tsx scripts/build.ts <theme>`.
  console.log("\n(LLM call not yet implemented -- see TODO in this file.)");
};

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
