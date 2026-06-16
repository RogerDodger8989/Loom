import path from 'path';
import fs from 'fs';
import db from '../config/database';

export function computeTrashPath(filePath: string): string {
  const libraryPaths = db.prepare('SELECT path FROM library_paths').all() as Array<{ path: string }>;
  let libraryBase = '';
  for (const lp of libraryPaths) {
    const normalizedLp = lp.path.replace(/[/\\]+$/, '');
    if (filePath.startsWith(normalizedLp + path.sep) || filePath.startsWith(normalizedLp + '/')) {
      libraryBase = normalizedLp;
      break;
    }
  }
  if (!libraryBase) {
    libraryBase = path.dirname(path.dirname(filePath));
  }
  const relative = filePath.substring(libraryBase.length).replace(/^[/\\]/, '');
  return path.join(libraryBase, '.trash', relative);
}
