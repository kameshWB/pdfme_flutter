import * as esbuild from 'esbuild';
import { copyFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');
const outDirs = [
  join(root, 'assets', 'pdfme'),
  join(root, 'android', 'src', 'main', 'assets', 'pdfme'),
  join(root, 'ios', 'pdfme_flutter', 'Sources', 'pdfme_flutter', 'Resources'),
];

for (const dir of outDirs) {
  mkdirSync(dir, { recursive: true });
}

const primaryOut = join(outDirs[0], 'engine.js');

await esbuild.build({
  entryPoints: [join(__dirname, 'src', 'engine.js')],
  bundle: true,
  outfile: primaryOut,
  format: 'iife',
  platform: 'browser',
  target: ['es2020'],
  minify: true,
  sourcemap: false,
  logLevel: 'info',
  // Keep browser globals; pdfme barcode path needs canvas + window.
  define: {
    'process.env.NODE_ENV': '"production"',
  },
  banner: {
    js: '/* pdfme Flutter mobile engine – generated, do not edit */',
  },
});

const htmlSrc = join(__dirname, 'src', 'engine.html');
for (const dir of outDirs) {
  if (dir !== outDirs[0]) {
    copyFileSync(primaryOut, join(dir, 'engine.js'));
  }
  copyFileSync(htmlSrc, join(dir, 'engine.html'));
}

console.log('Built engine.js →', outDirs.join(', '));
