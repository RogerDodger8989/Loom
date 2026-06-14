const fs = require('fs');
let t = fs.readFileSync('src/services/rating_sync.ts', 'utf8');
t = t.replace(/\\\$\{/g, '${');
fs.writeFileSync('src/services/rating_sync.ts', t);
