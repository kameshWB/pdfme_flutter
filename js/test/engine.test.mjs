import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { generate } from '@pdfme/generator';
import { text } from '@pdfme/schemas';

const __dirname = dirname(fileURLToPath(import.meta.url));

test('pdfme generate produces valid PDF', async () => {
  const pdf = await generate({
    template: {
      basePdf: { width: 210, height: 297, padding: [20, 20, 20, 20] },
      schemas: [
        [
          {
            name: 'customerName',
            type: 'text',
            position: { x: 20, y: 30 },
            width: 100,
            height: 10,
          },
        ],
      ],
    },
    inputs: [{ customerName: 'John Doe' }],
    plugins: { text },
  });

  assert.ok(pdf instanceof Uint8Array);
  assert.equal(String.fromCharCode(pdf[0], pdf[1], pdf[2], pdf[3]), '%PDF');
  assert.ok(pdf.length > 100);
});

test('bundled engine.js includes PdfmeMobile', () => {
  const src = readFileSync(
    join(__dirname, '..', '..', 'assets', 'pdfme', 'engine.js'),
    'utf8',
  );
  assert.ok(src.includes('PdfmeMobile'));
  assert.ok(src.length > 100_000);
});
