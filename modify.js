const fs = require('fs');
const file = 'frontend/lib/screens/dashboard_screen.dart';
let content = fs.readFileSync(file, 'utf8');

const target = 'if (_serverName.isNotEmpty)\\r\\n                                    Text(\\r\\n                                      _serverName,\\r\\n                                      style: TextStyle(\\r\\n                                        color: Colors.white.withValues(alpha: 0.38),\\r\\n                                        fontSize: 11,\\r\\n                                        fontWeight: FontWeight.w500,\\r\\n                                        letterSpacing: 0.5,\\r\\n                                      ),\\r\\n                                    ),';

const targetLf = target.replace(/\\r\\n/g, '\\n');

const addition = `\\n                                  Text(\\n                                    _currentUsername(),\\n                                    style: TextStyle(\\n                                      color: Colors.white.withValues(alpha: 0.38),\\n                                      fontSize: 11,\\n                                      fontWeight: FontWeight.w500,\\n                                      letterSpacing: 0.5,\\n                                    ),\\n                                  ),`;

if (content.includes(target)) {
    content = content.replace(target, target + addition.replace(/\\n/g, '\\r\\n'));
} else if (content.includes(targetLf)) {
    content = content.replace(targetLf, targetLf + addition);
} else {
    console.error("Target string not found!");
}

fs.writeFileSync(file, content);
