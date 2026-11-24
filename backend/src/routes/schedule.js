// POST /api/schedule/parse — read a timetable with Gemini (does not save anything)
// Body: { text } or { image: "<base64>", mime_type: "image/jpeg" }
// Returns: { courses: [{ code, name, days[], start_min, end_min, room }], note, model }

import { Router } from 'express';
import { requireAuth } from '../middleware/auth.js';
import { readSchedule } from '../services/schedule-reader.js';

const router = Router();
router.use(requireAuth);

const IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']);
const MAX_IMAGE_BYTES = 3 * 1024 * 1024; // base64 must stay under Vercel's 4.5 MB body limit

router.post('/parse', async (req, res) => {
  const text = typeof req.body.text === 'string' ? req.body.text.trim() : '';
  let image = null;

  if (typeof req.body.image === 'string' && req.body.image.length > 0) {
    const mimeType = String(req.body.mime_type || 'image/jpeg').toLowerCase();
    if (!IMAGE_TYPES.has(mimeType)) {
      return res.status(400).json({ error: `Unsupported image type ${mimeType}` });
    }
    const data = req.body.image.replace(/^data:[^;]+;base64,/, '');
    if (Buffer.byteLength(data, 'base64') > MAX_IMAGE_BYTES) {
      return res.status(413).json({ error: 'Image is too large (max 3 MB). Try a screenshot instead of a full-size photo.' });
    }
    image = { data, mimeType };
  }

  if (!image && !text) return res.status(400).json({ error: 'Send text or an image' });
  if (text.length > 4000) return res.status(400).json({ error: 'Text is too long' });

  try {
    const result = await readSchedule({ text, image });
    res.json(result);
  } catch (err) {
    console.error('Schedule read failed:', err.message);
    res.status(502).json({ error: 'Could not read the schedule right now. Try again in a moment.' });
  }
});

export default router;
