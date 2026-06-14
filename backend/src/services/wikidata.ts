import axios from 'axios';
import db from '../config/database';

/**
 * Wikidata SPARQL Integration för Smarta Samlingar
 * Hämtar filmer som t.ex. vunnit Oscar för Best Original Score eller där Hans Zimmer varit kompositör.
 */

export async function fetchOscarWinningScores() {
  const query = `
    SELECT ?movie ?movieLabel ?imdbId WHERE {
      ?movie wdt:P31 wd:Q11424;          # instans av film
             p:P166 ?awardStat.          # har vunnit pris
      ?awardStat ps:P166 wd:Q488651.     # Academy Award for Best Original Score
      ?movie wdt:P345 ?imdbId.           # har IMDb-id
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }
    LIMIT 100
  `;

  try {
    const response = await axios.get('https://query.wikidata.org/sparql', {
      params: { query, format: 'json' },
      headers: { 'User-Agent': 'LoomMediaServer/1.0' }
    });

    const results = response.data.results.bindings.map((b: any) => ({
      title: b.movieLabel.value,
      imdbId: b.imdbId.value
    }));

    return results;
  } catch (error) {
    console.error('[Wikidata] Misslyckades att hämta Oscar-vinnare:', error);
    return [];
  }
}

export async function createSmartCollections() {
  const oscarScores = await fetchOscarWinningScores();
  
  if (oscarScores.length > 0) {
    const imdbIds = oscarScores.map((o: any) => o.imdbId);
    
    // Hitta dessa filmer i vår lokala databas
    const placeholders = imdbIds.map(() => '?').join(',');
    const localMovies = db.prepare(`
      SELECT id, title FROM media_items 
      WHERE imdb_id IN (${placeholders})
    `).all(...imdbIds) as any[];

    if (localMovies.length > 0) {
      console.log('[Smarta Samlingar] Skapar samling för Oscar-vinnande filmmusik med', localMovies.length, 'titlar.');
      // Här kan logik läggas till för att spara detta i en "collections"-tabell om det finns,
      // eller märka filmerna med en specifik tagg i media_metadata.
    }
  }
}
