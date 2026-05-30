import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';
import axios from 'axios';
import { tmdbService } from '../services/tmdb';
import { v4 as uuidv4 } from 'uuid';

interface MediaQueryParams {
  mergeVersions?: string; // 'true' or 'false'
}

export default async function mediaRoutes(fastify: FastifyInstance) {
  
  // Set up auth guard hook for all media routes
  fastify.addHook('preValidation', async (request, reply) => {
    try {
      await request.jwtVerify();
    } catch (err) {
      reply.code(401).send({ error: 'Unauthorized: Access token required' });
    }
  });

  // GET /api/media/movies
  // Retrieves movies with automatic SQL-level content filtering based on user restrictions
  fastify.get(
    '/api/media/movies',
    async (request: FastifyRequest<{ Querystring: MediaQueryParams }>, reply: FastifyReply) => {
      const user = request.user as { id: string; username: string; role: string };
      const mergeVersions = request.query.mergeVersions !== 'false'; // Default to true (merged mode)

      try {
        // Query to get all movies that are NOT restricted for this user
        // Excludes matches on GENRE, RATING, or KEYWORD restriction patterns completely at the DB layer
        const moviesQuery = `
          SELECT mi.* FROM media_items mi
          WHERE mi.type = 'Movie'
          AND mi.id NOT IN (
            SELECT mm.media_item_id 
            FROM media_metadata mm
            JOIN user_restrictions ur ON ur.user_id = ?
            WHERE 
              (ur.restriction_type = 'GENRE' AND mm.metadata_key = 'genre' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'RATING' AND mm.metadata_key = 'rating' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'KEYWORD' AND mm.metadata_key = 'keyword' AND mm.metadata_value LIKE '%' || ur.restriction_value || '%')
          )
        `;

        const rawMovies = db.prepare(moviesQuery).all(user.id) as Array<{
          id: string;
          title: string;
          type: string;
          tmdb_id: string | null;
          imdb_id: string | null;
          file_path: string;
          added_at: string;
          poster_path: string | null;
          fanart_path: string | null;
          plot: string | null;
          year: number | null;
          genre: string | null;
        }>;

        // Fetch metadata for each movie
        const moviesWithMetadata = rawMovies.map(movie => {
          const metadataRows = db.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(movie.id) as Array<{ metadata_key: string; metadata_value: string }>;

          const metadata: Record<string, string> = {};
          metadataRows.forEach(row => {
            metadata[row.metadata_key] = row.metadata_value;
          });

          return {
            ...movie,
            metadata,
            resolution: metadata.resolution || '1080p'
          };
        });

        if (mergeVersions) {
          // Merged Mode: group movies by their TMDB ID or title if TMDB ID is missing
          const mergedMovies: Record<string, any> = {};

          moviesWithMetadata.forEach(movie => {
            const groupKey = movie.tmdb_id || movie.title;
            
            if (!mergedMovies[groupKey]) {
              mergedMovies[groupKey] = {
                id: movie.id,
                title: movie.title,
                type: movie.type,
                tmdb_id: movie.tmdb_id,
                imdb_id: movie.imdb_id,
                poster_path: movie.poster_path,
                fanart_path: movie.fanart_path,
                plot: movie.plot,
                year: movie.year,
                genre: movie.genre || movie.metadata.genre || 'Movie',
                added_at: movie.added_at,
                metadata: movie.metadata,
                versions: []
              };
            }

            mergedMovies[groupKey].versions.push({
              id: movie.id,
              file_path: movie.file_path,
              resolution: movie.resolution
            });
          });

          return reply.send(Object.values(mergedMovies));
        } else {
          // Separated Mode: Return items individually and add a clear visual badge indicator
          const badgedMovies = moviesWithMetadata.map(movie => ({
            ...movie,
            resolution_badge: movie.resolution // e.g. "4K" or "1080p"
          }));

          return reply.send(badgedMovies);
        }
      } catch (err) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to retrieve movies' });
      }
    }
  );

  // GET /api/media/items/:id
  // Retrieves full details for a specific media item (Plex-like Media Details page)
  fastify.get(
    '/api/media/items/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const user = request.user as { id: string; username: string; role: string };
      const { id } = request.params;

      try {
        // Fetch base media item
        const movie = db.prepare(`SELECT * FROM media_items WHERE id = ?`).get(id) as any;
        if (!movie) {
          return reply.code(404).send({ error: 'Media item not found' });
        }

        // Check user restrictions (if restricted, return 403)
        const restrictions = db.prepare(`
          SELECT ur.restriction_type, ur.restriction_value
          FROM user_restrictions ur
          WHERE ur.user_id = ?
        `).all(user.id) as any[];

        // Fetch metadata
        const metadataRows = db.prepare(`
          SELECT metadata_key, metadata_value 
          FROM media_metadata 
          WHERE media_item_id = ?
        `).all(movie.id) as Array<{ metadata_key: string; metadata_value: string }>;

        const metadata: Record<string, any> = {};
        metadataRows.forEach(row => {
          try {
            // Try to parse JSON for cast/ratings
            metadata[row.metadata_key] = JSON.parse(row.metadata_value);
          } catch (e) {
            metadata[row.metadata_key] = row.metadata_value;
          }
        });

        // Simple restriction check
        if (restrictions.length > 0) {
          const genre = movie.genre || metadata.genre;
          const rating = metadata.rating;
          for (const r of restrictions) {
            if (r.restriction_type === 'GENRE' && genre === r.restriction_value) {
              return reply.code(403).send({ error: 'Access denied due to genre restriction' });
            }
          }
        }

        // Return combined data
        return {
          id: movie.id,
          title: movie.title,
          type: movie.type,
          plot: movie.plot,
          year: movie.year,
          genre: movie.genre || metadata.genre || 'Movie',
          poster_path: movie.poster_path,
          fanart_path: movie.fanart_path,
          tmdb_id: movie.tmdb_id,
          imdb_id: movie.imdb_id,
          collection_name: movie.collection_name,
          collection_id: movie.collection_id,
          director: movie.director,
          original_title: movie.original_title,
          file_path: movie.file_path,
          added_at: movie.added_at,
          metadata: metadata, // includes 'cast', 'ratings' etc
          versions: [{
            id: movie.id,
            file_path: movie.file_path,
            resolution: metadata.resolution || '1080p'
          }]
        };

      } catch (error: any) {
        request.log.error(error);
        return reply.code(500).send({ error: 'Failed to fetch media details', details: error.message });
      }
    }
  );

  // GET /api/media/shows
  // Retrieves shows with SQL-level restriction filters applied
  fastify.get(
    '/api/media/shows',
    async (request: FastifyRequest, reply: FastifyReply) => {
      const user = request.user as { id: string; username: string; role: string };

      try {
        const showsQuery = `
          SELECT mi.* FROM media_items mi
          WHERE mi.type = 'Show'
          AND mi.id NOT IN (
            SELECT mm.media_item_id 
            FROM media_metadata mm
            JOIN user_restrictions ur ON ur.user_id = ?
            WHERE 
              (ur.restriction_type = 'GENRE' AND mm.metadata_key = 'genre' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'RATING' AND mm.metadata_key = 'rating' AND mm.metadata_value = ur.restriction_value)
              OR (ur.restriction_type = 'KEYWORD' AND mm.metadata_key = 'keyword' AND mm.metadata_value LIKE '%' || ur.restriction_value || '%')
          )
        `;

        const rawShows = db.prepare(showsQuery).all(user.id) as Array<{
          id: string;
          title: string;
          type: string;
          tmdb_id: string | null;
          imdb_id: string | null;
          file_path: string | null;
          added_at: string;
        }>;

        const showsWithEpisodes = rawShows.map(show => {
          // Get metadata
          const metadataRows = db.prepare(`
            SELECT metadata_key, metadata_value 
            FROM media_metadata 
            WHERE media_item_id = ?
          `).all(show.id) as Array<{ metadata_key: string; metadata_value: string }>;

          const metadata: Record<string, string> = {};
          metadataRows.forEach(row => {
            metadata[row.metadata_key] = row.metadata_value;
          });

          // Get episodes list
          const episodes = db.prepare(`
            SELECT id, season_number, episode_number, title, file_path 
            FROM episodes 
            WHERE show_id = ?
            ORDER BY season_number ASC, episode_number ASC
          `).all(show.id);

          return {
            ...show,
            metadata,
            episodes
          };
        });

        return reply.send(showsWithEpisodes);
      } catch (err) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to retrieve shows' });
      }
    }
  );

  // GET /api/people/:id
  // Retrieves bio and local-library matched movie credits for actors/directors
  fastify.get(
    '/api/people/:id',
    async (request: FastifyRequest<{ Params: { id: string } }>, reply: FastifyReply) => {
      const apiKeyRow = db.prepare("SELECT value FROM system_settings WHERE key = 'TMDB_API_KEY'").get() as { value: string } | undefined;
      if (!apiKeyRow || !apiKeyRow.value) {
        return reply.code(400).send({ error: 'TMDB API key not configured' });
      }
      const { id } = request.params;
      const prefLang = (db.prepare("SELECT value FROM system_settings WHERE key = 'METADATA_LANGUAGE'").get() as { value: string } | undefined)?.value || 'sv-SE';

      try {
        // 1. Fetch biographical info
        const personRes = await axios.get(`https://api.themoviedb.org/3/person/${id}`, {
          params: { api_key: apiKeyRow.value, language: prefLang }
        });
        const person = personRes.data;

        // 2. Fetch movie credits
        const creditsRes = await axios.get(`https://api.themoviedb.org/3/person/${id}/movie_credits`, {
          params: { api_key: apiKeyRow.value, language: prefLang }
        });
        
        const castCredits = creditsRes.data.cast || [];
        const crewCredits = creditsRes.data.crew || [];

        // Find all directed movies
        const directedMovies = crewCredits.filter((c: any) => c.job === 'Director');

        // 3. Match against local library movies!
        const localMovies = db.prepare(`SELECT id, title, year, tmdb_id, poster_path FROM media_items WHERE type = 'Movie'`).all() as any[];

        const matchLocal = (tmdbId: any, title: string) => {
          return localMovies.find(m => (m.tmdb_id && tmdbId && m.tmdb_id.toString() === tmdbId.toString()) || m.title.toLowerCase() === title.toLowerCase());
        };

        const mappedCast = castCredits.map((c: any) => {
          const localMatch = matchLocal(c.id, c.title);
          return {
            id: c.id,
            title: c.title,
            character: c.character,
            release_date: c.release_date,
            year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
            poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
            local_id: localMatch ? localMatch.id : null
          };
        }).sort((a: any, b: any) => (b.year || 0) - (a.year || 0));

        const mappedCrew = directedMovies.map((c: any) => {
          const localMatch = matchLocal(c.id, c.title);
          return {
            id: c.id,
            title: c.title,
            job: c.job,
            release_date: c.release_date,
            year: c.release_date ? parseInt(c.release_date.substring(0, 4), 10) : null,
            poster_path: c.poster_path ? `https://image.tmdb.org/t/p/w500${c.poster_path}` : null,
            local_id: localMatch ? localMatch.id : null
          };
        }).sort((a: any, b: any) => (b.year || 0) - (a.year || 0));

        return reply.send({
          id: person.id,
          name: person.name,
          biography: person.biography,
          birthday: person.birthday,
          deathday: person.deathday,
          place_of_birth: person.place_of_birth,
          profile_path: person.profile_path ? `https://image.tmdb.org/t/p/w500${person.profile_path}` : null,
          imdb_id: person.imdb_id,
          cast: mappedCast,
          crew: mappedCrew
        });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to fetch person details', details: err.message });
      }
    }
  );

  // GET /api/media/items/:id/search-tmdb
  fastify.get(
    '/api/media/items/:id/search-tmdb',
    async (request: FastifyRequest<{ Querystring: { query: string; year?: string } }>, reply: FastifyReply) => {
      const { query, year } = request.query;
      const parsedYear = year ? parseInt(year, 10) : undefined;
      try {
        const results = await tmdbService.searchMovieCandidates(query, parsedYear);
        return results.map((m: any) => ({
          id: m.id,
          title: m.title,
          original_title: m.original_title,
          release_date: m.release_date,
          year: m.release_date ? parseInt(m.release_date.substring(0, 4), 10) : null,
          poster_path: m.poster_path ? tmdbService.getImageUrl(m.poster_path, 'w500') : null
        }));
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to search TMDB', details: err.message });
      }
    }
  );

  // POST /api/media/items/:id/match
  fastify.post(
    '/api/media/items/:id/match',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { tmdbId: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { tmdbId } = request.body;

      try {
        const tmdbData = await tmdbService.fetchMovieById(tmdbId);
        if (!tmdbData) {
          return reply.code(404).send({ error: 'TMDB movie details not found' });
        }

        // Get genres
        const genre = tmdbData.genres ? tmdbData.genres.map((g: any) => g.name).join(', ') : 'Movie';
        
        // Director
        let director = null;
        if (tmdbData.credits && tmdbData.credits.crew) {
          const dirObj = tmdbData.credits.crew.find((c: any) => c.job === 'Director');
          if (dirObj) director = dirObj.name;
        }

        // Collection
        let collectionName = null;
        let collectionId = null;
        if (tmdbData.belongs_to_collection) {
          collectionName = tmdbData.belongs_to_collection.name;
          collectionId = tmdbData.belongs_to_collection.id.toString();
        }

        const poster_path = tmdbService.getImageUrl(tmdbData.poster_path, 'w500');
        const fanart_path = tmdbService.getImageUrl(tmdbData.backdrop_path, 'original');
        const year = tmdbData.release_date ? parseInt(tmdbData.release_date.substring(0, 4), 10) : null;

        // Update database media_item entry
        db.prepare(`
          UPDATE media_items 
          SET title = ?, plot = ?, year = ?, genre = ?, poster_path = ?, fanart_path = ?, tmdb_id = ?, imdb_id = ?, collection_name = ?, collection_id = ?, director = ?, original_title = ?
          WHERE id = ?
        `).run(
          tmdbData.title,
          tmdbData.overview || null,
          year,
          genre,
          poster_path,
          fanart_path,
          tmdbData.id.toString(),
          tmdbData.imdb_id || null,
          collectionName,
          collectionId,
          director,
          tmdbData.original_title || null,
          id
        );

        // Sub helper to upsert metadata
        const upsertMeta = (key: string, value: string) => {
          db.prepare(`
            INSERT INTO media_metadata (id, media_item_id, metadata_key, metadata_value) 
            VALUES (?, ?, ?, ?)
            ON CONFLICT(media_item_id, metadata_key) DO UPDATE SET metadata_value=excluded.metadata_value
          `).run(uuidv4(), id, key, value);
        };

        // Add additional metadata
        if (tmdbData.vote_average) {
          upsertMeta('ratings', JSON.stringify({ tmdb: tmdbData.vote_average }));
        }

        if (tmdbData.credits && tmdbData.credits.cast) {
          const cast = tmdbData.credits.cast.slice(0, 15).map((c: any) => ({
            id: c.id,
            name: c.name,
            character: c.character,
            profile_path: tmdbService.getImageUrl(c.profile_path, 'w500')
          }));
          upsertMeta('cast', JSON.stringify(cast));
        }

        if (tmdbData['watch/providers'] && tmdbData['watch/providers'].results) {
          upsertMeta('watch_providers', JSON.stringify(tmdbData['watch/providers'].results));
        }

        if (tmdbData.videos && tmdbData.videos.results) {
          const trailerObj = tmdbData.videos.results.find((v: any) => v.site === 'YouTube' && v.type === 'Trailer');
          if (trailerObj) {
            upsertMeta('trailer_url', `https://www.youtube.com/watch?v=${trailerObj.key}`);
          }
        }

        // Fetch OMDb Awards
        const omdbKey = tmdbService.getSetting('OMDB_API_KEY');
        if (omdbKey && tmdbData.imdb_id) {
          try {
            const omdbRes = await axios.get(`http://www.omdbapi.com/`, {
              params: { apikey: omdbKey, i: tmdbData.imdb_id }
            });
            if (omdbRes.data && omdbRes.data.Awards) {
              upsertMeta('awards', omdbRes.data.Awards);
            }
          } catch (omdbErr) {
            console.error('[ManualMatch] OMDb API awards fetch failed:', omdbErr);
          }
        }

        return reply.send({ success: true });
      } catch (err: any) {
        console.error(err);
        return reply.code(500).send({ error: 'Failed to manual-match media item', details: err.message });
      }
    }
  );

  // ─────────────────────────────────────────────────────────────
  // Playlist Routes
  // ─────────────────────────────────────────────────────────────

  // POST /api/playlists — Create a new playlist
  fastify.post(
    '/api/playlists',
    async (request: FastifyRequest<{ Body: { name: string } }>, reply: FastifyReply) => {
      const { name } = request.body;
      if (!name || !name.trim()) {
        return reply.code(400).send({ error: 'Playlist name is required' });
      }
      try {
        const id = `pl_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        db.prepare(`
          CREATE TABLE IF NOT EXISTS playlists (
            id TEXT PRIMARY KEY,
            name TEXT UNIQUE NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `).run();
        db.prepare(`INSERT INTO playlists (id, name) VALUES (?, ?)`).run(id, name.trim());
        return reply.status(201).send({ id, name: name.trim() });
      } catch (err: any) {
        if (err.message?.includes('UNIQUE')) {
          return reply.code(409).send({ error: 'Playlist already exists' });
        }
        return reply.code(500).send({ error: 'Failed to create playlist', details: err.message });
      }
    }
  );

  // POST /api/playlists/:id/items — Add a media item to a playlist
  fastify.post(
    '/api/playlists/:id/items',
    async (request: FastifyRequest<{ Params: { id: string }; Body: { mediaItemId: string } }>, reply: FastifyReply) => {
      const { id } = request.params;
      const { mediaItemId } = request.body;
      if (!mediaItemId) {
        return reply.code(400).send({ error: 'mediaItemId is required' });
      }
      try {
        db.prepare(`
          CREATE TABLE IF NOT EXISTS playlist_items (
            id TEXT PRIMARY KEY,
            playlist_id TEXT NOT NULL,
            media_item_id TEXT NOT NULL,
            added_at DATETIME DEFAULT CURRENT_TIMESTAMP
          )
        `).run();
        const itemId = `pli_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
        db.prepare(`INSERT INTO playlist_items (id, playlist_id, media_item_id) VALUES (?, ?, ?)`)
          .run(itemId, id, mediaItemId);
        return reply.status(201).send({ id: itemId, playlist_id: id, media_item_id: mediaItemId });
      } catch (err: any) {
        return reply.code(500).send({ error: 'Failed to add item to playlist', details: err.message });
      }
    }
  );
}
