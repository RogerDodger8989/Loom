/**
 * MusicBrainz enrichment service for Loom.
 * Ported and adapted from MusicMaster (Electron app in this repo).
 */

import { MusicBrainzApi } from 'musicbrainz-api';
import axios from 'axios';
import fs from 'fs';
import path from 'path';
import db from '../config/database';
import { MUSIC_COVERS_DIR } from './soundtrack_scanner';

const mbApi = new MusicBrainzApi({
  appName: 'Loom',
  appVersion: '1.0.0',
  appContactInfo: 'https://github.com/RogerDodger8989/Loom',
});

// MusicBrainz requires max 1 req/sec + User-Agent (handled by musicbrainz-api package)
const RATE_LIMIT_MS = 1100;

// 1-hour in-memory cache
const queryCache = new Map<string, { data: any; timestamp: number }>();
const CACHE_TTL_MS = 60 * 60 * 1000;

function applyRateLimit(): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, RATE_LIMIT_MS));
}

function getFromCache(key: string): any | null {
  const cached = queryCache.get(key);
  if (cached && Date.now() - cached.timestamp < CACHE_TTL_MS) return cached.data;
  queryCache.delete(key);
  return null;
}

function setCache(key: string, data: any): void {
  queryCache.set(key, { data, timestamp: Date.now() });
}

// ── Cover Art Archive ────────────────────────────────────────────────────────

const CAA_BASE = 'https://coverartarchive.org';

async function downloadImage(url: string, destPath: string): Promise<boolean> {
  try {
    const response = await axios.get(url, { responseType: 'arraybuffer', timeout: 15000 });
    fs.writeFileSync(destPath, Buffer.from(response.data));
    return true;
  } catch {
    return false;
  }
}

/** Fetch all cover art images for a release MBID from Cover Art Archive */
async function fetchCoverArtArchive(releaseMbid: string): Promise<Array<{
  id: string; types: string[]; url: string; thumbnail500: string; front: boolean; back: boolean;
}>> {
  try {
    const cacheKey = `caa:${releaseMbid}`;
    const cached = getFromCache(cacheKey);
    if (cached) return cached;

    const res = await axios.get(`${CAA_BASE}/release/${releaseMbid}`, { timeout: 10000 });
    if (!res.data?.images) return [];

    const images = (res.data.images as any[]).map((img: any) => ({
      id: String(img.id),
      types: img.types || [],
      url: img.image,
      thumbnail500: img.thumbnails?.['500'] || img.thumbnails?.['250'] || img.image,
      front: !!img.front,
      back: !!img.back,
    }));

    setCache(cacheKey, images);
    return images;
  } catch (e: any) {
    if (e.response?.status !== 404) {
      console.error(`[MB] CAA fetch failed for ${releaseMbid}:`, e.message);
    }
    return [];
  }
}

// ── Release (Album) enrichment ────────────────────────────────────────────────

export async function enrichAlbum(albumId: string): Promise<void> {
  const album = db.prepare('SELECT * FROM music_albums WHERE id = ?').get(albumId) as any;
  if (!album) return;

  const releaseMbid = album.musicbrainz_album_id;
  if (!releaseMbid) {
    console.log(`[MB] Album ${albumId} has no MBID, skipping enrichment`);
    return;
  }

  console.log(`[MB] Enriching album: ${album.title} (${releaseMbid})`);

  try {
    const cacheKey = `release:${releaseMbid}`;
    let release: any = getFromCache(cacheKey);

    if (!release) {
      await applyRateLimit();
      release = await (mbApi as any).lookup('release', releaseMbid, [
        'artists', 'labels', 'recordings', 'isrcs', 'release-groups',
        'media', 'tags', 'genres', 'ratings', 'url-rels', 'artist-rels',
        'label-rels', 'recording-level-rels', 'work-level-rels',
      ]);
      setCache(cacheKey, release);
    }

    // Extract label + catalog number
    const labelInfo = release['label-info']?.[0];
    const label = labelInfo?.label?.name || null;
    const catalogNumber = labelInfo?.['catalog-number'] || null;

    // Extract release group type
    const rg = release['release-group'];
    const releaseType = rg?.['primary-type'] || null;
    const secondaryTypes = JSON.stringify(rg?.['secondary-types'] || []);

    // Extract genres/tags
    const genres = JSON.stringify(
      (release.genres || release.tags || []).map((g: any) => ({ name: g.name, votes: g.count || 0 }))
    );

    // Extract community rating
    const rating = release.rating?.value || null;
    const ratingVotes = release.rating?.['votes-count'] || 0;

    // Extract external URLs from url-rels
    const externalUrls: Record<string, string> = {};
    for (const rel of (release.relations || [])) {
      if (rel['target-type'] === 'url' && rel.url?.resource) {
        const url: string = rel.url.resource;
        const type: string = rel.type;
        if (type === 'discogs') externalUrls.discogs = url;
        else if (url.includes('spotify.com')) externalUrls.spotify = url;
        else if (url.includes('music.apple.com') || url.includes('itunes.apple.com')) externalUrls.apple_music = url;
        else if (url.includes('bandcamp.com')) externalUrls.bandcamp = url;
        else if (type === 'allmusic') externalUrls.allmusic = url;
        else if (url.includes('amazon.')) externalUrls.amazon = url;
        else if (url.includes('youtube.com')) externalUrls.youtube = url;
      }
    }
    externalUrls.musicbrainz = `https://musicbrainz.org/release/${releaseMbid}`;

    // Extract media format
    const mediaFormat = release.media?.[0]?.format || null;

    // Update music_albums
    db.prepare(`
      UPDATE music_albums SET
        release_group_mbid = COALESCE(release_group_mbid, ?),
        release_date = COALESCE(release_date, ?),
        release_country = COALESCE(release_country, ?),
        release_status = COALESCE(release_status, ?),
        barcode = COALESCE(barcode, ?),
        packaging = COALESCE(packaging, ?),
        label = COALESCE(label, ?),
        catalog_number = COALESCE(catalog_number, ?),
        release_type = COALESCE(release_type, ?),
        secondary_types = COALESCE(secondary_types, ?),
        genres = COALESCE(genres, ?),
        rating = COALESCE(rating, ?),
        rating_votes = COALESCE(rating_votes, ?),
        external_urls = ?,
        script = COALESCE(script, ?),
        language = COALESCE(language, ?),
        mb_enriched_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(
      rg?.id || null,
      release.date || null,
      release.country || null,
      release.status || null,
      release.barcode || null,
      release.packaging || null,
      label,
      catalogNumber,
      releaseType,
      secondaryTypes,
      genres,
      rating,
      ratingVotes,
      JSON.stringify(externalUrls),
      release.script || null,
      release['text-language'] || null,
      albumId,
    );

    console.log(`[MB] ✓ Album metadata enriched: ${album.title}`);

    // Fetch cover art from Cover Art Archive
    await enrichAlbumCovers(albumId, releaseMbid);

    // Enrich artist if we have their MBID
    const artistCredit = release['artist-credit']?.[0];
    const artistMbid = artistCredit?.artist?.id;
    if (artistMbid && album.artist_id) {
      const artistRow = db.prepare('SELECT musicbrainz_id, mb_enriched_at FROM music_artists WHERE id = ?')
        .get(album.artist_id) as any;
      if (artistRow && !artistRow.mb_enriched_at) {
        if (!artistRow.musicbrainz_id) {
          db.prepare('UPDATE music_artists SET musicbrainz_id = ? WHERE id = ?').run(artistMbid, album.artist_id);
        }
        await enrichArtist(album.artist_id).catch(e => console.error('[MB] Artist enrichment failed:', e));
      }
    }

    // Enrich tracks with recording-level data
    await enrichAlbumTracks(albumId, release).catch(e =>
      console.error('[MB] Track enrichment failed:', e)
    );

  } catch (e: any) {
    console.error(`[MB] Failed to enrich album ${albumId}:`, e.message || e);
  }
}

/** Fetch and store all cover art types from Cover Art Archive */
async function enrichAlbumCovers(albumId: string, releaseMbid: string): Promise<void> {
  const album = db.prepare('SELECT cover_path FROM music_albums WHERE id = ?').get(albumId) as any;

  const images = await fetchCoverArtArchive(releaseMbid);
  if (images.length === 0) return;

  // Store all images in music_album_images
  for (const img of images) {
    const existing = db.prepare('SELECT id FROM music_album_images WHERE album_id = ? AND mb_image_id = ?')
      .get(albumId, img.id);
    if (existing) continue;

    const typeLabel = img.front ? 'front' : img.back ? 'back' : (img.types[0] || 'other').toLowerCase();

    const { v4: uuidv4 } = await import('uuid');
    db.prepare(`
      INSERT INTO music_album_images (id, album_id, type, url, mb_image_id, added_at)
      VALUES (?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
    `).run(uuidv4(), albumId, typeLabel, img.thumbnail500, img.id);
  }

  // Download front cover if we don't have one yet
  if (!album?.cover_path) {
    const frontImage = images.find(i => i.front);
    if (frontImage) {
      const localPath = path.join(MUSIC_COVERS_DIR, `${albumId}.jpg`);
      const downloaded = await downloadImage(frontImage.url, localPath);
      if (downloaded) {
        db.prepare('UPDATE music_albums SET cover_path = ? WHERE id = ?').run(localPath, albumId);
        console.log(`[MB] ✓ Downloaded front cover for album ${albumId}`);
      }
    }
  }

  // Also try release-group cover if still no cover
  const updatedAlbum = db.prepare('SELECT cover_path, release_group_mbid FROM music_albums WHERE id = ?').get(albumId) as any;
  if (!updatedAlbum?.cover_path && updatedAlbum?.release_group_mbid) {
    try {
      const res = await axios.get(`${CAA_BASE}/release-group/${updatedAlbum.release_group_mbid}`, {
        timeout: 10000, maxRedirects: 3,
      });
      if (res.data?.images?.length > 0) {
        const rgFront = res.data.images.find((i: any) => i.front) || res.data.images[0];
        const localPath = path.join(MUSIC_COVERS_DIR, `${albumId}.jpg`);
        const downloaded = await downloadImage(rgFront.image, localPath);
        if (downloaded) {
          db.prepare('UPDATE music_albums SET cover_path = ? WHERE id = ?').run(localPath, albumId);
          console.log(`[MB] ✓ Downloaded release-group cover for album ${albumId}`);
        }
      }
    } catch { /* no RG cover */ }
  }
}

// ── Artist enrichment ────────────────────────────────────────────────────────

export async function enrichArtist(artistId: string): Promise<void> {
  const artist = db.prepare('SELECT * FROM music_artists WHERE id = ?').get(artistId) as any;
  if (!artist?.musicbrainz_id) return;

  const mbid = artist.musicbrainz_id;
  console.log(`[MB] Enriching artist: ${artist.name} (${mbid})`);

  try {
    const cacheKey = `artist:${mbid}`;
    let mbArtist: any = getFromCache(cacheKey);
    if (!mbArtist) {
      await applyRateLimit();
      mbArtist = await mbApi.lookup('artist', mbid, ['aliases', 'tags', 'genres', 'ratings', 'url-rels']);
      setCache(cacheKey, mbArtist);
    }

    // External URLs
    const externalUrls: Record<string, string> = {};
    for (const rel of ((mbArtist as any).relations || [])) {
      if (rel['target-type'] === 'url' && rel.url?.resource) {
        const url: string = rel.url.resource;
        const type: string = rel.type;
        if (type === 'official homepage') externalUrls.website = url;
        else if (type === 'discogs') externalUrls.discogs = url;
        else if (type === 'last.fm') externalUrls.lastfm = url;
        else if (type === 'allmusic') externalUrls.allmusic = url;
        else if (type === 'wikipedia') externalUrls.wikipedia = url;
        else if (type === 'wikidata') externalUrls.wikidata = url;
        else if (type === 'youtube') externalUrls.youtube = url;
        else if (type === 'imdb') externalUrls.imdb = url;
        else if (type === 'songkick') externalUrls.songkick = url;
        else if (url.includes('spotify.com')) externalUrls.spotify = url;
        else if (url.includes('instagram.com')) externalUrls.instagram = url;
        else if (url.includes('twitter.com') || url.includes('x.com')) externalUrls.twitter = url;
        else if (url.includes('facebook.com')) externalUrls.facebook = url;
        else if (url.includes('bandcamp.com')) externalUrls.bandcamp = url;
        else if (url.includes('soundcloud.com')) externalUrls.soundcloud = url;
        else if (url.includes('tiktok.com')) externalUrls.tiktok = url;
      }
    }
    externalUrls.musicbrainz = `https://musicbrainz.org/artist/${mbid}`;

    const genres = JSON.stringify(
      ((mbArtist as any).genres || (mbArtist as any).tags || []).map((g: any) => ({ name: g.name, votes: g.count || 0 }))
    );
    const aliases = JSON.stringify(
      ((mbArtist as any).aliases || []).map((a: any) => a.name)
    );

    const lifeSpan = (mbArtist as any)['life-span'];

    db.prepare(`
      UPDATE music_artists SET
        sort_name = COALESCE(sort_name, ?),
        type = COALESCE(type, ?),
        gender = COALESCE(gender, ?),
        area = COALESCE(area, ?),
        begin_date = COALESCE(begin_date, ?),
        end_date = COALESCE(end_date, ?),
        disambiguation = COALESCE(disambiguation, ?),
        aliases = ?,
        genres = ?,
        external_urls = ?,
        mb_enriched_at = CURRENT_TIMESTAMP
      WHERE id = ?
    `).run(
      (mbArtist as any)['sort-name'] || null,
      (mbArtist as any).type || null,
      (mbArtist as any).gender || null,
      (mbArtist as any).area?.name || null,
      lifeSpan?.begin || null,
      lifeSpan?.end || null,
      (mbArtist as any).disambiguation || null,
      aliases,
      genres,
      JSON.stringify(externalUrls),
      artistId,
    );

    console.log(`[MB] ✓ Artist enriched: ${artist.name}`);
  } catch (e: any) {
    console.error(`[MB] Failed to enrich artist ${artistId}:`, e.message || e);
  }
}

// ── Track enrichment ─────────────────────────────────────────────────────────

async function enrichAlbumTracks(albumId: string, release: any): Promise<void> {
  const tracks = db.prepare('SELECT * FROM music_tracks WHERE album_id = ?').all(albumId) as any[];
  if (tracks.length === 0) return;

  // Build a lookup map from recording MBID to track details from MB
  const mbTrackMap = new Map<string, any>();
  for (const media of (release.media || [])) {
    for (const mbTrack of (media.tracks || [])) {
      const recordingMbid = mbTrack.recording?.id;
      if (recordingMbid) {
        mbTrackMap.set(recordingMbid, mbTrack);
      }
    }
  }

  for (const track of tracks) {
    const recordingMbid = track.recording_mbid || track.musicbrainz_id;
    if (!recordingMbid || track.mb_enriched_at) continue;

    try {
      await applyRateLimit();
      const recording = await (mbApi as any).lookup('recording', recordingMbid, [
        'artist-credits', 'isrcs', 'tags', 'genres', 'work-rels',
      ]);

      const isrcs = (recording as any).isrcs || [];
      const genres = JSON.stringify(
        ((recording as any).genres || (recording as any).tags || [])
          .map((g: any) => ({ name: g.name, votes: g.count || 0 }))
      );

      // Find work relation for composers/lyricists
      let composers: Array<{ name: string; mbid: string }> = [];
      let lyricists: Array<{ name: string; mbid: string }> = [];
      let arrangers: Array<{ name: string; mbid: string }> = [];
      let workMbid: string | null = null;
      let iswc: string | null = null;
      let workType: string | null = null;

      const workRel = ((recording as any).relations || []).find((r: any) => r['target-type'] === 'work');
      if (workRel?.work?.id) {
        workMbid = workRel.work.id;
        iswc = workRel.work.iswcs?.[0] || null;
        workType = workRel.work.type || null;

        // Fetch work details for composers
        try {
          await applyRateLimit();
          const work = await (mbApi as any).lookup('work', workRel.work.id, ['artist-rels']);
          for (const rel of ((work as any).relations || [])) {
            if (rel['target-type'] === 'artist' && rel.artist) {
              const person = { name: rel.artist.name, mbid: rel.artist.id };
              if (rel.type === 'composer') composers.push(person);
              else if (rel.type === 'lyricist') lyricists.push(person);
              else if (rel.type === 'arranger' || rel.type === 'orchestrator') arrangers.push(person);
            }
          }
        } catch { /* work lookup failed */ }
      }

      db.prepare(`
        UPDATE music_tracks SET
          isrc = COALESCE(isrc, ?),
          first_release_date = COALESCE(first_release_date, ?),
          genres = ?,
          composers = ?,
          lyricists = ?,
          arrangers = ?,
          work_mbid = COALESCE(work_mbid, ?),
          iswc = COALESCE(iswc, ?),
          work_type = COALESCE(work_type, ?),
          mb_enriched_at = CURRENT_TIMESTAMP
        WHERE id = ?
      `).run(
        isrcs[0] || null,
        (recording as any)['first-release-date'] || null,
        genres,
        JSON.stringify(composers),
        JSON.stringify(lyricists),
        JSON.stringify(arrangers),
        workMbid,
        iswc,
        workType,
        track.id,
      );
    } catch (e: any) {
      console.error(`[MB] Track enrichment failed for ${track.title}:`, e.message);
    }
  }
}

// ── Search (for manual matching) ─────────────────────────────────────────────

export async function searchReleases(query: string, artist?: string): Promise<any[]> {
  const q = artist ? `artist:"${artist}" AND release:"${query}"` : query;
  const cacheKey = `search:release:${q}`;
  const cached = getFromCache(cacheKey);
  if (cached) return cached;

  try {
    await applyRateLimit();
    let result = await mbApi.search('release', { query: q });

    if (!result.releases || result.releases.length === 0) {
      await applyRateLimit();
      result = await mbApi.search('release', { query: `${artist || ''} ${query}`.trim() });
    }

    const releases = (result.releases || []).map((rel: any) => ({
      id: rel.id,
      title: rel.title,
      artist: rel['artist-credit']?.[0]?.name || 'Unknown',
      date: rel.date,
      country: rel.country,
      status: rel.status,
      label: rel['label-info']?.[0]?.label?.name || null,
      catalogNumber: rel['label-info']?.[0]?.['catalog-number'] || null,
      trackCount: rel['track-count'],
      score: rel.score,
      coverUrl: `https://coverartarchive.org/release/${rel.id}/front-250`,
    }));

    setCache(cacheKey, releases);
    return releases;
  } catch (e: any) {
    console.error('[MB] Release search failed:', e.message);
    return [];
  }
}

/** Match an album to a MusicBrainz release MBID, then enrich it */
export async function matchAndEnrichAlbum(albumId: string, releaseMbid: string): Promise<void> {
  db.prepare('UPDATE music_albums SET musicbrainz_album_id = ?, mb_enriched_at = NULL WHERE id = ?')
    .run(releaseMbid, albumId);
  await enrichAlbum(albumId);
}

// ── Background batch enrichment ───────────────────────────────────────────────

let _enrichRunning = false;

export async function enrichAlbumsInBackground(albumIds: string[]): Promise<void> {
  if (_enrichRunning) {
    console.log('[MB] Background enrichment already running, skipping');
    return;
  }
  _enrichRunning = true;
  console.log(`[MB] Starting background enrichment for ${albumIds.length} albums...`);
  try {
    for (const albumId of albumIds) {
      await enrichAlbum(albumId);
    }
    console.log('[MB] Background enrichment complete');
  } finally {
    _enrichRunning = false;
  }
}

/** Enrich all albums that have a MBID but haven't been enriched yet */
export async function enrichAllPending(): Promise<void> {
  const albums = db.prepare(`
    SELECT id FROM music_albums
    WHERE musicbrainz_album_id IS NOT NULL AND musicbrainz_album_id != ''
      AND (mb_enriched_at IS NULL OR mb_enriched_at = '')
  `).all() as { id: string }[];

  if (albums.length === 0) {
    console.log('[MB] No albums pending enrichment');
    return;
  }

  await enrichAlbumsInBackground(albums.map(a => a.id));
}
