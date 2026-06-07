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
exports.buildApp = buildApp;
const fastify_1 = __importDefault(require("fastify"));
const cors_1 = __importDefault(require("@fastify/cors"));
const jwt_1 = __importDefault(require("@fastify/jwt"));
const dotenv = __importStar(require("dotenv"));
const auth_1 = __importDefault(require("./routes/auth"));
const library_1 = __importStar(require("./routes/library"));
const media_1 = __importDefault(require("./routes/media"));
const markers_1 = __importDefault(require("./routes/markers"));
const settings_1 = __importDefault(require("./routes/settings"));
const oauth_1 = __importDefault(require("./routes/oauth"));
const sync_1 = __importDefault(require("./routes/sync"));
const playback_1 = __importDefault(require("./routes/playback"));
const calendar_1 = __importDefault(require("./routes/calendar"));
const notifications_1 = __importDefault(require("./routes/notifications"));
const logs_1 = __importDefault(require("./routes/logs"));
const server_1 = __importDefault(require("./routes/server"));
const users_1 = __importDefault(require("./routes/users"));
const stats_1 = __importDefault(require("./routes/stats"));
const rss_1 = __importDefault(require("./routes/rss"));
const export_1 = __importDefault(require("./routes/export"));
const multipart_1 = __importDefault(require("@fastify/multipart"));
const log_store_1 = require("./services/log_store");
const rating_sync_1 = require("./services/rating_sync");
// Load environment variables
dotenv.config();
const isTest = process.env.NODE_ENV === 'test';
// Intercept console output into the in-memory log store (skip in test mode)
if (!isTest) {
    const _origLog = console.log.bind(console);
    const _origWarn = console.warn.bind(console);
    const _origError = console.error.bind(console);
    console.log = (...a) => { (0, log_store_1.addLog)('info', a.map(String).join(' ')); _origLog(...a); };
    console.warn = (...a) => { (0, log_store_1.addLog)('warn', a.map(String).join(' ')); _origWarn(...a); };
    console.error = (...a) => { (0, log_store_1.addLog)('error', a.map(String).join(' ')); _origError(...a); };
}
async function buildApp() {
    const app = (0, fastify_1.default)({
        logger: isTest ? false : {
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
    app.register(multipart_1.default, { limits: { fileSize: 100 * 1024 * 1024 } });
    app.register(cors_1.default, {
        origin: '*',
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Content-Type', 'Authorization']
    });
    const jwtSecret = process.env.JWT_SECRET || 'loom-offgrid-super-secret-key-1337-abc-xyz';
    app.register(jwt_1.default, { secret: jwtSecret });
    // Base health-check route
    app.get('/', async () => ({
        app: 'LOOM',
        description: 'API-driven headless offgrid media server',
        status: 'ONLINE',
        time: new Date().toISOString()
    }));
    // Register API Routes
    app.register(auth_1.default);
    app.register(library_1.default);
    app.register(media_1.default);
    app.register(markers_1.default);
    app.register(settings_1.default);
    app.register(oauth_1.default);
    app.register(sync_1.default);
    app.register(playback_1.default);
    app.register(calendar_1.default);
    app.register(notifications_1.default);
    app.register(logs_1.default);
    app.register(server_1.default);
    app.register(users_1.default);
    app.register(stats_1.default);
    app.register(rss_1.default);
    app.register(export_1.default);
    // Log every HTTP response to the in-memory log store (skip in test mode)
    if (!isTest) {
        app.addHook('onResponse', async (req, reply) => {
            const level = reply.statusCode >= 500 ? 'error' : reply.statusCode >= 400 ? 'warn' : 'info';
            (0, log_store_1.addLog)(level, `${req.method} ${req.url} → ${reply.statusCode}`);
        });
        app.addHook('onError', async (req, _reply, err) => {
            (0, log_store_1.addLog)('error', `${req.method} ${req.url} ✗ ${err.message}`);
        });
    }
    app.setErrorHandler((error, request, reply) => {
        app.log.error(error);
        if (error.statusCode) {
            return reply.code(error.statusCode).send({ error: error.message });
        }
        return reply.code(500).send({ error: 'Internal Server Error' });
    });
    return app;
}
// Start the real server only when not running under Jest
if (!isTest) {
    const PORT = parseInt(process.env.PORT || '8080', 10);
    const HOST = process.env.HOST || '0.0.0.0';
    const start = async () => {
        try {
            console.log('[Loom Server] Database status checked. Starting API listener...');
            const app = await buildApp();
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
            (0, library_1.setupFileWatchers)();
            (0, rating_sync_1.syncAllExternalData)().catch(e => {
                console.error('[Startup Sync] Failed to run syncAllExternalData:', e);
            });
            const syncIntervalMinutes = Number.parseInt(process.env.EXTERNAL_SYNC_INTERVAL_MINUTES || '45', 10);
            const safeIntervalMinutes = Number.isFinite(syncIntervalMinutes) && syncIntervalMinutes > 0
                ? syncIntervalMinutes
                : 45;
            setInterval(() => {
                (0, rating_sync_1.syncAllExternalData)().catch(e => {
                    console.error('[Scheduled Sync] Failed to run syncAllExternalData:', e);
                });
            }, safeIntervalMinutes * 60 * 1000);
            console.log(`[Sync] Scheduled external sync every ${safeIntervalMinutes} minutes.`);
        }
        catch (err) {
            console.error(err);
            process.exit(1);
        }
    };
    start();
}
