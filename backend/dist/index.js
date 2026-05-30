"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const fastify_1 = __importDefault(require("fastify"));
const cors_1 = __importDefault(require("@fastify/cors"));
const jwt_1 = __importDefault(require("@fastify/jwt"));
const dotenv = __importStar(require("dotenv"));
const auth_1 = __importDefault(require("./routes/auth"));
const library_1 = __importDefault(require("./routes/library"));
const media_1 = __importDefault(require("./routes/media"));
const settings_1 = __importDefault(require("./routes/settings"));
const oauth_1 = __importDefault(require("./routes/oauth"));
// Load environment variables
dotenv.config();
const app = (0, fastify_1.default)({
    logger: {
        transport: {
            target: 'pino-pretty',
            options: {
                colorize: true,
                translateTime: 'yyyy-mm-dd HH:MM:ss Z',
                ignore: 'pid,hostname'
            }
        }
    }
});
// Configure CORS - Crucial for local desktop and mobile/TV client requests
app.register(cors_1.default, {
    origin: '*',
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
    allowedHeaders: ['Content-Type', 'Authorization']
});
// Configure JWT Authentication
// In a production offgrid Docker image, this can be supplied via environment variable
const jwtSecret = process.env.JWT_SECRET || 'loom-offgrid-super-secret-key-1337-abc-xyz';
app.register(jwt_1.default, {
    secret: jwtSecret
});
// Declare a base test route
app.get('/', async () => {
    return {
        app: 'LOOM',
        description: 'API-driven headless offgrid media server',
        status: 'ONLINE',
        time: new Date().toISOString()
    };
});
// Register API Routes
app.register(auth_1.default);
app.register(library_1.default);
app.register(media_1.default);
app.register(settings_1.default);
app.register(oauth_1.default);
// Global Error Handler
app.setErrorHandler((error, request, reply) => {
    app.log.error(error);
    if (error.statusCode) {
        return reply.code(error.statusCode).send({ error: error.message });
    }
    return reply.code(500).send({ error: 'Internal Server Error' });
});
// Start the server
const PORT = parseInt(process.env.PORT || '8080', 10);
const HOST = process.env.HOST || '0.0.0.0'; // Bind to all interfaces for local TV/Docker network access
const start = async () => {
    try {
        // Check DB status
        console.log('[Loom Server] Database status checked. Starting API listener...');
        await app.listen({ port: PORT, host: HOST });
        console.log(`
██╗      ██████╗  ██████╗ ███╗   ███╗
██║     ██╔═══██╗██╔═══██╗████╗ ████║
██║     ██║   ██║██║   ██║██╔████╔██║
██║     ██║   ██║██║   ██║██║╚██╔╝██║
███████╗╚██████╔╝╚██████╔╝██║ ╚═╝ ██║
╚══════╝ ╚═════╝  ╚═════╝ ╚═╝     ╚═╝
    Headless Media Server is now online!
    👉 Server listening on http://${HOST}:${PORT}
    `);
    }
    catch (err) {
        app.log.error(err);
        process.exit(1);
    }
};
start();
