import { FastifyInstance, FastifyRequest, FastifyReply } from 'fastify';
import db from '../config/database';

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
}
