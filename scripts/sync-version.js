const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const packageJson = require(path.join(repoRoot, "package.json"));
const tocPath = path.join(repoRoot, "addon", "Wforged", "Wforged.toc");
const version = String(packageJson.version);
const toc = fs.readFileSync(tocPath, "utf8");
const versionLine = `## Version: ${version}`;
const hasVersionLine = /^## Version:/m.test(toc);
let updated = toc.replace(/^## Version:[^\r\n]*\r?$/m, versionLine);

if (!hasVersionLine) {
  updated = toc.replace(/^(## Author:[^\r\n]*\r?\n)/m, `$1${versionLine}\n`);
}

if (!hasVersionLine && updated === toc) {
  throw new Error(`Could not update addon version in ${tocPath}`);
}

if (updated !== toc) {
  fs.writeFileSync(tocPath, updated);
  console.log(`Synced TOC version to ${version}`);
}
