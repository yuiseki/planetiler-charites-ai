/**
 * Build both schema and style for a theme.
 *   tsx scripts/build.ts <theme-name>
 */
import { spawnSync } from "node:child_process";
import process from "node:process";

const themeName = process.argv[2];
if (!themeName) {
  console.error("Usage: build.ts <theme-name>");
  process.exit(1);
}

const run = (script: string) => {
  const result = spawnSync(
    "npx",
    ["tsx", `scripts/${script}.ts`, themeName],
    { stdio: "inherit" },
  );
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
};

run("build-schema");
run("build-style");
