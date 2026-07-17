const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const addonName = "Wforged";
const addonSourceDir = path.join(repoRoot, "addon", addonName);
const addonsRoot = process.env.ASCENSION_ADDONS_DIR
  || "C:\\Ascension\\Launcher\\resources\\ascension-live\\Interface\\AddOns";
const addonTargetDir = path.join(addonsRoot, addonName);
const tocPath = path.join(addonSourceDir, `${addonName}.toc`);

function fail(message) {
  console.error(message);
  process.exit(1);
}

if (!fs.existsSync(addonSourceDir)) {
  fail(`Addon source folder not found: ${addonSourceDir}`);
}

if (!fs.existsSync(tocPath)) {
  fail(`Missing TOC file: ${tocPath}`);
}

if (!fs.existsSync(addonsRoot)) {
  fail(`Ascension AddOns folder not found: ${addonsRoot}`);
}

fs.rmSync(addonTargetDir, { recursive: true, force: true });
fs.cpSync(addonSourceDir, addonTargetDir, { recursive: true });

console.log(`Deployed ${addonName} to ${addonTargetDir}`);
