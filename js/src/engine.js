/**
 * Mobile wrapper around @pdfme/generator for headless WebView execution.
 * Exposed as globalThis.PdfmeMobile.
 */
import { generate } from '@pdfme/generator';
import {
  text,
  multiVariableText,
  image,
  signature,
  svg,
  table,
  line,
  rectangle,
  ellipse,
  barcodes,
  dateTime,
  date,
  time,
  select,
  checkbox,
  radioGroup,
  list,
  circleMark,
} from '@pdfme/schemas';

const barcodePlugins = Object.fromEntries(
  Object.entries(barcodes).map(([key, plugin]) => [key, plugin]),
);

/** Disable remote network APIs inside the embedded runtime. */
function installOfflineGuards() {
  const rejectNetwork = () =>
    Promise.reject(new Error('Network requests are disabled in pdfme_flutter'));

  try {
    globalThis.fetch = rejectNetwork;
  } catch (_) {
    // ignore
  }

  try {
    if (typeof XMLHttpRequest !== 'undefined') {
      XMLHttpRequest.prototype.open = function blockedOpen() {
        throw new Error('Network requests are disabled in pdfme_flutter');
      };
    }
  } catch (_) {
    // ignore
  }
}

installOfflineGuards();

function resolvePlugins(extra = {}) {
  const fromGlobal =
    typeof globalThis !== 'undefined' && globalThis.__pdfmeExtraPlugins
      ? globalThis.__pdfmeExtraPlugins
      : {};

  return {
    text,
    multiVariableText,
    image,
    signature,
    svg,
    table,
    line,
    rectangle,
    ellipse,
    dateTime,
    date,
    time,
    select,
    checkbox,
    radioGroup,
    list,
    circleMark,
    ...barcodePlugins,
    qrcode: barcodes.qrcode,
    ...fromGlobal,
    ...extra,
  };
}

function uint8ToBase64(bytes) {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function base64ToUtf8(b64) {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  if (typeof TextDecoder !== 'undefined') {
    return new TextDecoder('utf-8').decode(bytes);
  }
  let out = '';
  for (let i = 0; i < bytes.length; i += 1) {
    out += String.fromCharCode(bytes[i]);
  }
  return out;
}

function isRemoteUrl(value) {
  return typeof value === 'string' && /^(https?:)?\/\//i.test(value.trim());
}

function assertOfflinePayload(template, inputs) {
  const basePdf = template.basePdf;
  if (isRemoteUrl(basePdf)) {
    throw Object.assign(new Error(
      'Remote basePdf URLs are not supported. Use a blankPdf object or a data:application/pdf;base64,... value.',
    ), { code: 'INVALID_TEMPLATE' });
  }

  for (let i = 0; i < inputs.length; i += 1) {
    const row = inputs[i];
    if (!row || typeof row !== 'object') continue;
    for (const [key, value] of Object.entries(row)) {
      if (isRemoteUrl(value)) {
        throw Object.assign(new Error(
          `Input "${key}" must not be a remote URL. Use a data: URI for images/signatures.`,
        ), { code: 'INVALID_INPUT' });
      }
    }
  }
}

function normalizeError(error) {
  const message =
    error && typeof error === 'object' && 'message' in error
      ? String(error.message)
      : String(error ?? 'Unknown PDF generation error');

  let code =
    error && typeof error === 'object' && error.code
      ? String(error.code)
      : 'GENERATION_ERROR';
  const lower = message.toLowerCase();
  if (code === 'GENERATION_ERROR') {
    if (lower.includes('invalid argument') || lower.includes('zod')) {
      code = 'INVALID_TEMPLATE_OR_INPUT';
    } else if (lower.includes('is not found in plugins') || lower.includes('plugins')) {
      code = 'UNSUPPORTED_SCHEMA';
    } else if (lower.includes('font')) {
      code = 'FONT_ERROR';
    } else if (lower.includes('image') || lower.includes('png') || lower.includes('jpg')) {
      code = 'INVALID_IMAGE';
    } else if (lower.includes('required')) {
      code = 'INVALID_INPUT';
    } else if (lower.includes('memory') || lower.includes('allocation')) {
      code = 'MEMORY_ERROR';
    } else if (lower.includes('network requests are disabled')) {
      code = 'NETWORK_BLOCKED';
    }
  }

  return { code, message };
}

function postResult(requestId, result) {
  try {
    if (globalThis.PdfmeBridge && typeof globalThis.PdfmeBridge.onResult === 'function') {
      globalThis.PdfmeBridge.onResult(requestId, JSON.stringify(result));
      return;
    }
  } catch (_) {
    // ignore
  }
  try {
    if (
      globalThis.webkit &&
      globalThis.webkit.messageHandlers &&
      globalThis.webkit.messageHandlers.PdfmeBridge
    ) {
      globalThis.webkit.messageHandlers.PdfmeBridge.postMessage({
        type: 'result',
        requestId,
        payload: result,
      });
    }
  } catch (_) {
    // ignore
  }
}

/**
 * @param {{ template: object, inputs: object[], options?: object, plugins?: object }} payload
 */
async function generatePdf(payload) {
  try {
    if (!payload || typeof payload !== 'object') {
      return {
        error: {
          code: 'INVALID_INPUT',
          message: 'Payload must be an object with template and inputs.',
        },
      };
    }

    const { template, inputs, options = {}, plugins: extraPlugins } = payload;

    if (!template || typeof template !== 'object') {
      return {
        error: {
          code: 'INVALID_TEMPLATE',
          message: 'template must be a pdfme-compatible object.',
        },
      };
    }

    if (!Array.isArray(inputs) || inputs.length === 0) {
      return {
        error: {
          code: 'INVALID_INPUT',
          message: 'inputs must be a non-empty array (pdfme requires at least one input object).',
        },
      };
    }

    assertOfflinePayload(template, inputs);

    const pdf = await generate({
      template,
      inputs,
      options,
      plugins: resolvePlugins(extraPlugins || {}),
    });

    if (!(pdf instanceof Uint8Array) || pdf.length === 0) {
      return {
        error: {
          code: 'GENERATION_ERROR',
          message: 'pdfme returned empty or invalid PDF data.',
        },
      };
    }

    if (pdf[0] !== 0x25 || pdf[1] !== 0x50 || pdf[2] !== 0x44 || pdf[3] !== 0x46) {
      return {
        error: {
          code: 'GENERATION_ERROR',
          message: 'Generated output is not a valid PDF (missing %PDF header).',
        },
      };
    }

    return { pdfBase64: uint8ToBase64(pdf) };
  } catch (error) {
    return { error: normalizeError(error) };
  }
}

/**
 * Native hosts call this with a base64-encoded JSON envelope:
 * { requestId, templateJson, inputsJson, optionsJson }
 */
async function runRequest(envelopeB64) {
  let requestId = 'unknown';
  try {
    const envelope = JSON.parse(base64ToUtf8(envelopeB64));
    requestId = String(envelope.requestId || 'unknown');
    const template = JSON.parse(envelope.templateJson);
    const inputs = JSON.parse(envelope.inputsJson);
    const options = JSON.parse(envelope.optionsJson || '{}');
    const result = await generatePdf({ template, inputs, options });
    postResult(requestId, result);
  } catch (error) {
    postResult(requestId, { error: normalizeError(error) });
  }
}

const PdfmeMobile = {
  version: '6.1.12',
  generate: generatePdf,
  runRequest,
  resolvePlugins,
};

globalThis.PdfmeMobile = PdfmeMobile;

export { PdfmeMobile, generatePdf, runRequest };
