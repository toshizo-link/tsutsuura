import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
const dir = path.dirname(fileURLToPath(import.meta.url));
const direction = JSON.parse(fs.readFileSync(path.join(dir, '../preview-art-direction.json')));
const sha256 = data => crypto.createHash('sha256').update(data).digest('hex');
const files = direction.pages.map(page => {
  const source = fs.readFileSync(path.join(dir, '..', page.source));
  if (sha256(source) !== page.sourceSHA256) throw new Error(`Source modified: ${page.source}`);
  const name = path.basename(page.source);
  const file = fs.readFileSync(path.join(dir, 'exports', name));
  const width = file.readUInt32BE(16), height = file.readUInt32BE(20), colorType = file[25];
  if (width !== 1320 || height !== 2868 || colorType !== 2) throw new Error(`Invalid opaque RGB export: ${name}`);
  return { name, width, height, colorType: 'RGB, opaque', sha256: sha256(file), source: page.source, sourceSHA256: page.sourceSHA256, headline: page.headline, subline: page.subline };
});
const manifest = { generatedAt: new Date().toISOString(), method: 'Browser rendering of native HTML/CSS with unmodified source PNG image elements', font: 'Kaisotai-Next-UP-B bundled with the app', imageGeometry: { width: 950, height: 2064.090909, sourceAspectRatio: '1320:2868', objectFit: 'contain', crop: 'none' }, files };
fs.writeFileSync(path.join(dir, 'exports/manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(`Verified ${files.length} opaque RGB 1320×2868 exports and all unchanged source hashes.`);
