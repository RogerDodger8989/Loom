const http = require('http');

// Get pairing code from command line arguments
const code = process.argv[2];

if (!code) {
  console.log('\n❌ Error: No pairing code provided!');
  console.log('Usage: node pair.js <CODE>');
  console.log('Example: node pair.js ABCD\n');
  process.exit(1);
}

const upperCode = code.toUpperCase();

function post(url, headers, body) {
  return new Promise((resolve, reject) => {
    const parsedUrl = new URL(url);
    const options = {
      hostname: parsedUrl.hostname,
      port: parsedUrl.port || 80,
      path: parsedUrl.pathname,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...headers
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => data += chunk);
      res.on('end', () => {
        try {
          resolve(JSON.parse(data));
        } catch (e) {
          resolve(data);
        }
      });
    });

    req.on('error', (err) => reject(err));
    req.write(JSON.stringify(body));
    req.end();
  });
}

async function main() {
  try {
    console.log('Logging in with default admin account...');
    const loginRes = await post('http://localhost:8080/api/auth/login', {}, {
      username: 'admin',
      password: 'adminpassword'
    });

    if (!loginRes.token) {
      console.error('Login failed:', loginRes);
      return;
    }

    console.log(`Login successful! Confirming pairing code: "${upperCode}"...`);
    const confirmRes = await post('http://localhost:8080/api/auth/pair/confirm', {
      'Authorization': `Bearer ${loginRes.token}`
    }, {
      code: upperCode,
      deviceName: 'Chrome Web Client'
    });

    if (confirmRes.success) {
      console.log(`\n🎉 Success: ${confirmRes.message}\n`);
    } else {
      console.log(`\n❌ Pairing failed:`, confirmRes.error || confirmRes);
    }
  } catch (err) {
    console.error('\n❌ Error during pairing:', err.message);
  }
}

main();
