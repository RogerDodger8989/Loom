import { execSync, spawn } from 'child_process';
import { v4 as uuidv4 } from 'uuid';
import db from '../config/database';
import ffmpegInstaller from '@ffmpeg-installer/ffmpeg';
const ffprobeInstaller = require('@ffprobe-installer/ffprobe');

// ─────────────────────────────────────────────────────────
// Method 1 — Chapter marker extraction
// ─────────────────────────────────────────────────────────

export interface ChapterResult {
  title: string | null;
  startSeconds: number;
  endSeconds: number;
}

export function extractChapters(filePath: string): ChapterResult[] {
  try {
    const out = execSync(
      `"${ffprobeInstaller.path}" -v quiet -print_format json -show_chapters "${filePath.replace(/"/g, '\\"')}"`,
      { maxBuffer: 4 * 1024 * 1024 }
    ).toString();
    const data = JSON.parse(out);
    const chapters: any[] = data.chapters || [];
    return chapters.map((ch: any) => ({
      title: ch.tags?.title || null,
      startSeconds: parseFloat(ch.start_time ?? '0'),
      endSeconds: parseFloat(ch.end_time ?? '0'),
    }));
  } catch (e) {
    return [];
  }
}

export function storeChapterMarkers(
  chapters: ChapterResult[],
  mediaItemId: string | null,
  episodeId: string | null,
  totalDurationSeconds: number
): void {
  if (chapters.length === 0) return;

  // Clear old chapter markers for this item
  if (mediaItemId) {
    db.prepare(`DELETE FROM media_markers WHERE media_item_id = ? AND source = 'chapter'`).run(mediaItemId);
  }
  if (episodeId) {
    db.prepare(`DELETE FROM media_markers WHERE episode_id = ? AND source = 'chapter'`).run(episodeId);
  }

  const upsert = db.prepare(`
    INSERT INTO media_markers (id, media_item_id, episode_id, marker_type, start_time_seconds, end_time_seconds, title, source)
    VALUES (?, ?, ?, ?, ?, ?, ?, 'chapter')
  `);

  for (let i = 0; i < chapters.length; i++) {
    const ch = chapters[i];
    const isFirst = i === 0;
    const isLast = i === chapters.length - 1;

    // Classify: INTRO if first chapter ends before 10 minutes and there are other chapters
    // OUTRO if last chapter starts after 85% of total duration
    let markerType = 'CHAPTER';
    if (chapters.length >= 2) {
      if (isFirst && ch.endSeconds > 0 && ch.endSeconds <= 600) {
        markerType = 'INTRO';
      } else if (isLast && totalDurationSeconds > 0 && ch.startSeconds >= totalDurationSeconds * 0.82) {
        markerType = 'OUTRO';
      }
    }

    upsert.run(
      uuidv4(),
      mediaItemId,
      episodeId,
      markerType,
      ch.startSeconds,
      ch.endSeconds,
      ch.title
    );
  }
}

export async function scanChaptersForItem(
  filePath: string,
  mediaItemId: string | null,
  episodeId: string | null
): Promise<number> {
  const chapters = extractChapters(filePath);
  if (chapters.length === 0) return 0;

  // Get total duration
  let durationSec = 0;
  try {
    const probeOut = execSync(
      `"${ffprobeInstaller.path}" -v quiet -print_format json -show_format "${filePath.replace(/"/g, '\\"')}"`,
      { maxBuffer: 2 * 1024 * 1024 }
    ).toString();
    durationSec = parseFloat(JSON.parse(probeOut).format?.duration ?? '0');
  } catch (_) {}

  storeChapterMarkers(chapters, mediaItemId, episodeId, durationSec);
  return chapters.length;
}

// ─────────────────────────────────────────────────────────
// Method 2 — Audio fingerprinting (Goertzel algorithm)
// ─────────────────────────────────────────────────────────

const SAMPLE_RATE = 11025;
const FRAME_SIZE = 1408; // ~128ms per frame at 11025Hz (Chromaprint-compatible)
const PROBE_FREQUENCIES = [300, 1000, 3000, 7000]; // Hz — 4 frequency bands

function goertzel(samples: Int16Array, targetFreq: number): number {
  const N = samples.length;
  const k = Math.round(N * targetFreq / SAMPLE_RATE);
  const omega = 2 * Math.PI * k / N;
  const coeff = 2 * Math.cos(omega);
  let s1 = 0, s2 = 0;
  for (let i = 0; i < N; i++) {
    const s = (samples[i] / 32768) + coeff * s1 - s2;
    s2 = s1;
    s1 = s;
  }
  return s1 * s1 + s2 * s2 - coeff * s1 * s2;
}

function popcount(n: number): number {
  n = n - ((n >> 1) & 0x55555555);
  n = (n & 0x33333333) + ((n >> 2) & 0x33333333);
  return (((n + (n >> 4)) & 0x0f0f0f0f) * 0x01010101) >>> 24;
}

export function computeFingerprint(pcmBuffer: Buffer): number[] {
  const fp: number[] = [];
  const bytesPerFrame = FRAME_SIZE * 2; // Int16 = 2 bytes per sample
  let prevEnergies = PROBE_FREQUENCIES.map(() => 0);

  for (let i = 0; i + bytesPerFrame <= pcmBuffer.length; i += bytesPerFrame) {
    const samples = new Int16Array(
      pcmBuffer.buffer.slice(pcmBuffer.byteOffset + i, pcmBuffer.byteOffset + i + bytesPerFrame)
    );
    const energies = PROBE_FREQUENCIES.map(f => goertzel(samples, f));

    // 4-bit signature: bit k = 1 if energy in band k increased vs prev frame
    let bits = 0;
    for (let b = 0; b < PROBE_FREQUENCIES.length; b++) {
      if (energies[b] > prevEnergies[b]) bits |= (1 << b);
    }
    prevEnergies = energies;

    // Pack 8 consecutive 4-bit frames into one 32-bit integer
    const frameIdx = Math.floor(i / bytesPerFrame);
    const packIdx = Math.floor(frameIdx / 8);
    const bitPos = (frameIdx % 8) * 4;
    if (bitPos === 0) fp.push(0);
    fp[fp.length - 1] = (fp[fp.length - 1] | (bits << bitPos)) >>> 0;
  }

  return fp;
}

export async function extractAudioFingerprint(
  filePath: string,
  maxSeconds = 600
): Promise<{ fingerprint: number[]; durationSeconds: number }> {
  return new Promise((resolve, reject) => {
    const ffArgs = [
      '-t', maxSeconds.toString(),
      '-i', filePath,
      '-map', '0:a:0',
      '-ac', '1',
      '-ar', SAMPLE_RATE.toString(),
      '-f', 's16le',
      'pipe:1'
    ];

    const ff = spawn(ffmpegInstaller.path, ffArgs, { stdio: ['ignore', 'pipe', 'ignore'] });
    const chunks: Buffer[] = [];

    ff.stdout.on('data', (d: Buffer) => chunks.push(d));
    ff.on('close', (code) => {
      if (chunks.length === 0) {
        reject(new Error('FFmpeg produced no audio output'));
        return;
      }
      const pcm = Buffer.concat(chunks);
      const fingerprint = computeFingerprint(pcm);
      const durationSeconds = pcm.length / (SAMPLE_RATE * 2);
      resolve({ fingerprint, durationSeconds });
    });
    ff.on('error', reject);
  });
}

export function storeFingerprintForEpisode(
  episodeId: string,
  fingerprint: number[],
  durationSeconds: number
): void {
  db.prepare(`
    INSERT INTO audio_fingerprints (id, episode_id, fingerprint_data, duration_seconds)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(episode_id) DO UPDATE SET fingerprint_data=excluded.fingerprint_data, duration_seconds=excluded.duration_seconds, created_at=CURRENT_TIMESTAMP
  `).run(uuidv4(), episodeId, JSON.stringify(fingerprint), durationSeconds);
}

// ON CONFLICT needs a unique constraint — add it for episode_id
export function ensureFingerprintUniqueIndex(): void {
  try {
    db.exec(`CREATE UNIQUE INDEX IF NOT EXISTS idx_audio_fp_unique_episode ON audio_fingerprints(episode_id) WHERE episode_id IS NOT NULL`);
  } catch (_) {}
}

// ─────────────────────────────────────────────────────────
// Intro detection by comparing fingerprints
// ─────────────────────────────────────────────────────────

const UNITS_PER_SECOND = 1 / (FRAME_SIZE * 8 / SAMPLE_RATE); // fingerprint units per second
const MIN_INTRO_SECONDS = 15;
const MAX_INTRO_SEARCH_SECONDS = 600; // search first 10 minutes

interface IntroMatch {
  startInEp1: number;  // seconds
  startInEp2: number;
  durationSeconds: number;
  confidence: number;
}

export function findCommonIntro(fp1: number[], fp2: number[]): IntroMatch | null {
  const maxUnits = Math.floor(MAX_INTRO_SEARCH_SECONDS * UNITS_PER_SECOND);
  const windowUnits = Math.floor(MIN_INTRO_SECONDS * UNITS_PER_SECOND);

  const limit1 = Math.min(fp1.length, maxUnits);
  const limit2 = Math.min(fp2.length, maxUnits);

  let bestScore = 0;
  let best: IntroMatch | null = null;

  // Slide ep2's fingerprint over ep1, looking for best alignment
  for (let offset2 = 0; offset2 < limit2 - windowUnits; offset2++) {
    for (let offset1 = 0; offset1 < limit1 - windowUnits; offset1++) {
      let matches = 0;
      let run = 0;

      while (
        offset1 + run < limit1 &&
        offset2 + run < limit2 &&
        run < maxUnits
      ) {
        const hammingDist = popcount((fp1[offset1 + run] ^ fp2[offset2 + run]) >>> 0);
        if (hammingDist <= 10) { // out of 32 bits, <= 10 differ = good match
          matches++;
          run++;
        } else {
          break;
        }
      }

      if (run >= windowUnits) {
        const score = matches / run;
        if (score > bestScore) {
          bestScore = score;
          const secsPerUnit = (FRAME_SIZE * 8) / SAMPLE_RATE;
          best = {
            startInEp1: offset1 * secsPerUnit,
            startInEp2: offset2 * secsPerUnit,
            durationSeconds: run * secsPerUnit,
            confidence: score,
          };
        }
      }
    }
  }

  return bestScore >= 0.7 ? best : null;
}

export async function detectAndStoreIntroForShow(showId: string): Promise<{
  episodesProcessed: number;
  markersCreated: number;
}> {
  // Get all episodes that have fingerprints
  const rows = db.prepare(`
    SELECT e.id, e.show_id, e.season_number, e.episode_number, af.fingerprint_data
    FROM episodes e
    JOIN audio_fingerprints af ON af.episode_id = e.id
    WHERE e.show_id = ?
    ORDER BY e.season_number, e.episode_number
  `).all(showId) as Array<{
    id: string; show_id: string; season_number: number;
    episode_number: number; fingerprint_data: string;
  }>;

  if (rows.length < 2) return { episodesProcessed: rows.length, markersCreated: 0 };

  let markersCreated = 0;
  const introTimes: Map<string, { start: number; end: number }> = new Map();

  // Compare each episode pair to find the common intro
  for (let i = 0; i < Math.min(rows.length - 1, 5); i++) {
    for (let j = i + 1; j < Math.min(rows.length, i + 4); j++) {
      const fp1: number[] = JSON.parse(rows[i].fingerprint_data);
      const fp2: number[] = JSON.parse(rows[j].fingerprint_data);
      const match = findCommonIntro(fp1, fp2);
      if (!match) continue;

      // Store intro times for both episodes
      if (!introTimes.has(rows[i].id)) {
        introTimes.set(rows[i].id, { start: match.startInEp1, end: match.startInEp1 + match.durationSeconds });
      }
      if (!introTimes.has(rows[j].id)) {
        introTimes.set(rows[j].id, { start: match.startInEp2, end: match.startInEp2 + match.durationSeconds });
      }
    }
  }

  // Write markers for all episodes that have identified intro times
  for (const [epId, times] of introTimes) {
    // Delete old fingerprint-based INTRO marker
    db.prepare(`DELETE FROM media_markers WHERE episode_id = ? AND source = 'fingerprint' AND marker_type = 'INTRO'`).run(epId);

    db.prepare(`
      INSERT INTO media_markers (id, episode_id, marker_type, start_time_seconds, end_time_seconds, title, source)
      VALUES (?, ?, 'INTRO', ?, ?, 'Intro', 'fingerprint')
    `).run(uuidv4(), epId, times.start, times.end);
    markersCreated++;
  }

  // Apply the same intro window to episodes WITHOUT fingerprints in this show
  // by using the average detected intro window
  if (introTimes.size > 0) {
    const avgStart = [...introTimes.values()].reduce((s, t) => s + t.start, 0) / introTimes.size;
    const avgEnd = [...introTimes.values()].reduce((s, t) => s + t.end, 0) / introTimes.size;

    const unprocessed = db.prepare(`
      SELECT e.id FROM episodes e
      LEFT JOIN audio_fingerprints af ON af.episode_id = e.id
      WHERE e.show_id = ? AND af.id IS NULL
    `).all(showId) as Array<{ id: string }>;

    for (const ep of unprocessed) {
      db.prepare(`DELETE FROM media_markers WHERE episode_id = ? AND source = 'fingerprint' AND marker_type = 'INTRO'`).run(ep.id);
      db.prepare(`
        INSERT INTO media_markers (id, episode_id, marker_type, start_time_seconds, end_time_seconds, title, source)
        VALUES (?, ?, 'INTRO', ?, ?, 'Intro (estimated)', 'fingerprint')
      `).run(uuidv4(), ep.id, avgStart, avgEnd);
      markersCreated++;
    }
  }

  return { episodesProcessed: rows.length, markersCreated };
}
