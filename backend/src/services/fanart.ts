import axios from 'axios';
import db from '../config/database';

/**
 * Fanart.tv Integration
 * Hämtar extra artwork (som discart/cdart för vinyl-läget och clearlogos)
 */

const FANART_API_KEY = process.env.FANART_API_KEY || ''; // Måste sättas i .env

export async function fetchMovieDiscart(tmdbId: string): Promise<string | null> {
  if (!FANART_API_KEY) {
    console.warn('[Fanart.tv] API-nyckel saknas. Hoppar över hämtning av discart.');
    return null;
  }

  try {
    const response = await axios.get(`https://webservice.fanart.tv/v3/movies/${tmdbId}`, {
      headers: { 'api-key': FANART_API_KEY }
    });

    if (response.data && response.data.moviecdart && response.data.moviecdart.length > 0) {
      // Returnera den bäst rankade discarten (oftast index 0)
      return response.data.moviecdart[0].url;
    }
  } catch (error: any) {
    if (error.response && error.response.status === 404) {
      console.log(`[Fanart.tv] Ingen discart hittades för tmdb_id: ${tmdbId}`);
    } else {
      console.error('[Fanart.tv] Fel vid hämtning av discart:', error.message);
    }
  }
  
  return null;
}

export async function updateSoundtrackDiscart(movieId: string, tmdbId: string) {
  const discartUrl = await fetchMovieDiscart(tmdbId);
  
  if (discartUrl) {
    const row = db.prepare('SELECT metadata_value FROM media_metadata WHERE media_item_id = ? AND metadata_key = ?').get(movieId, 'soundtrack_data') as any;
    if (row) {
      try {
        const soundtrackData = JSON.parse(row.metadata_value);
        soundtrackData.discart_url = discartUrl;
        
        db.prepare(`
          UPDATE media_metadata 
          SET metadata_value = ? 
          WHERE media_item_id = ? AND metadata_key = 'soundtrack_data'
        `).run(JSON.stringify(soundtrackData), movieId);
        
        console.log(`[Fanart.tv] Uppdaterade discart för film ${movieId}`);
      } catch (e) {
        console.error('[Fanart.tv] Kunde inte parsa soundtrack_data:', e);
      }
    }
  }
}
