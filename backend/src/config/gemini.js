import { GoogleGenerativeAI } from '@google/generative-ai';

const key = process.env.GEMINI_API_KEY;
export const geminiConfigured = Boolean(key && key !== 'your-gemini-api-key');

if (!geminiConfigured) {
  console.warn('\n  ⚠  GEMINI_API_KEY is not set. Get a free key at https://aistudio.google.com/apikey\n');
}

// Free-tier models get "high demand" (503) and quota (429) errors from time to
// time, so we try a list in order. Override with GEMINI_MODEL=a,b,c in .env.
export const GEMINI_MODELS = (process.env.GEMINI_MODEL || 'gemini-flash-lite-latest,gemini-3-flash-preview,gemini-3.8-flash,gemini-flash-latest')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

const genAI = new GoogleGenerativeAI(key || 'missing');

const models = new Map(GEMINI_MODELS.map(name => [name, genAI.getGenerativeModel({
  model: name,
  generationConfig: {
    temperature: 0.4,
    responseMimeType: 'application/json',
  },
})]));

/** Errors worth retrying on the next model (overloaded, quota, model retired). */
function retryable(err) {
  const s = err?.status ?? Number(/\[(\d{3})/.exec(err?.message ?? '')?.[1]);
  return [404, 429, 500, 503].includes(s) || /timeout|abort|fetch failed|overloaded|unavailable/i.test(err?.message ?? '');
}

/**
 * Generate content, falling back through GEMINI_MODELS.
 * @param {string | Array} prompt  text, or an array of parts (text + { inlineData } images)
 * @param {{ timeout?: number }} [opts]
 * @returns {Promise<{ text: string, model: string }>}
 */
export async function generateJson(prompt, { timeout = 20_000 } = {}) {
  if (!geminiConfigured) throw new Error('GEMINI_API_KEY is not configured');
  let lastErr;
  for (const [name, model] of models) {
    try {
      const result = await model.generateContent(prompt, { timeout });
      return { text: result.response.text(), model: name };
    } catch (err) {
      lastErr = err;
      console.warn(`Gemini ${name} failed: ${err.message?.slice(0, 160)}`);
      if (!retryable(err)) break;
    }
  }
  throw lastErr;
}
