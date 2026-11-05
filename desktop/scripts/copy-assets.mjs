import { copyFile, mkdir } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const desktop = resolve(here, "..");
await mkdir(resolve(desktop, "ui", "assets"), { recursive: true });
// Keep the existing, separately licensed art byte-for-byte unchanged.
await copyFile(resolve(desktop, "..", "docs", "hero.gif"), resolve(desktop, "ui", "assets", "hero.gif"));
