const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const packageJson = require(path.join(repoRoot, "package.json"));
const tocPath = path.join(repoRoot, "addon", "Wforged", "Wforged.toc");
const version = String(packageJson.version);
const toc = fs.readFileSync(tocPath, "utf8");
const updated = toc.replace(/^## Version:.*$/m, `## Version: ${version}`);

if (updated === toc) {
  throw new Error(`Missing ## Version entry in ${tocPath}`);
}

if (updated !== toc) {
  fs.writeFileSync(tocPath, updated);
  console.log(`Synced TOC version to ${version}`);
}
