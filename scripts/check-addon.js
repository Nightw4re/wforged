const fs = require("fs");
const path = require("path");

const repoRoot = path.resolve(__dirname, "..");
const addonName = "Wforged";
const addonSourceDir = path.join(repoRoot, "addon", addonName);
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

for (const file of fs.readdirSync(addonSourceDir).filter((name) => name.endsWith('.lua'))) {
  const content = fs.readFileSync(path.join(addonSourceDir, file), 'utf8');
  if (content.includes('\u0000')) fail(`Invalid NUL byte in ${file}`);
}

console.log(`Addon source looks valid: ${addonSourceDir}`);
