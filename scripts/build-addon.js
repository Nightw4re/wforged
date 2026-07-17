const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const repoRoot = path.resolve(__dirname, "..");
const addonName = "Wforged";
const addonSourceDir = path.join(repoRoot, "addon", addonName);
const packageJson = require(path.join(repoRoot, "package.json"));
const distDir = path.join(repoRoot, "dist");
const archivePath = path.join(distDir, `${addonName}-${packageJson.version}.zip`);

if (!fs.existsSync(path.join(addonSourceDir, `${addonName}.toc`))) {
  console.error(`Missing addon source: ${addonSourceDir}`);
  process.exit(1);
}

fs.mkdirSync(distDir, { recursive: true });

const command = [
  "$ErrorActionPreference = 'Stop'",
  `Compress-Archive -LiteralPath '${addonSourceDir.replace(/'/g, "''")}' -DestinationPath '${archivePath.replace(/'/g, "''")}' -Force`,
].join("; ");
const result = spawnSync("powershell", ["-NoProfile", "-Command", command], { stdio: "inherit" });

if (result.status !== 0) {
  process.exit(result.status || 1);
}

console.log(`Built ${archivePath}`);
