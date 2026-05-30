"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.pairingService = void 0;
const database_1 = __importDefault(require("../config/database"));
class PairingService {
    // Keyed by code (uppercase alfanumeric, e.g. "X87B")
    activeCodes = new Map();
    // Keyed by deviceId
    activeDevices = new Map(); // deviceId -> code
    /**
     * Generates a random alphanumeric code of a specific length
     */
    generateCode(length = 4) {
        const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Excluded easily confused chars like I, O, 0, 1, 1
        let code = '';
        for (let i = 0; i < length; i++) {
            code += chars.charAt(Math.floor(Math.random() * chars.length));
        }
        return code;
    }
    /**
     * Requests a new pairing code for a specific Device ID
     */
    requestPairing(deviceId) {
        // Clean up any existing active requests for this device
        const existingCode = this.activeDevices.get(deviceId);
        if (existingCode) {
            this.activeCodes.delete(existingCode);
            this.activeDevices.delete(deviceId);
        }
        // Generate a unique code
        let code = this.generateCode();
        while (this.activeCodes.has(code)) {
            code = this.generateCode();
        }
        const expiresAt = Date.now() + 10 * 60 * 1000; // Valid for 10 minutes
        const pairing = {
            code,
            deviceId,
            expiresAt,
            paired: false
        };
        this.activeCodes.set(code, pairing);
        this.activeDevices.set(deviceId, code);
        console.log(`[Pairing] Created pairing code ${code} for device ${deviceId}. Expires at ${new Date(expiresAt).toISOString()}`);
        return { code, deviceId, expiresAt };
    }
    /**
     * Confirms a pairing request from an authenticated administrator / user screen.
     * Links the code to the confirming User's ID and persists it.
     */
    confirmPairing(code, userId, deviceName = 'Unknown Device') {
        const upperCode = code.toUpperCase().trim();
        const pairing = this.activeCodes.get(upperCode);
        if (!pairing) {
            console.log(`[Pairing] Confirm failed: Code ${upperCode} not found.`);
            return false;
        }
        if (Date.now() > pairing.expiresAt) {
            console.log(`[Pairing] Confirm failed: Code ${upperCode} has expired.`);
            this.activeCodes.delete(upperCode);
            this.activeDevices.delete(pairing.deviceId);
            return false;
        }
        // Update in-memory state so polling client will see it
        pairing.paired = true;
        pairing.userId = userId;
        // Persist device to DB
        try {
            const stmt = database_1.default.prepare(`
        INSERT OR REPLACE INTO paired_devices (device_id, user_id, device_name, paired_at)
        VALUES (?, ?, ?, CURRENT_TIMESTAMP)
      `);
            stmt.run(pairing.deviceId, userId, deviceName);
            console.log(`[Pairing] Confirmed code ${upperCode}. Device ${pairing.deviceId} is now paired with User ${userId}`);
            return true;
        }
        catch (err) {
            console.error(`[Pairing] Database error during confirmation:`, err);
            return false;
        }
    }
    /**
     * Checks the pairing status of a device.
     * If in-memory paired, returns JWT token info, and removes from memory.
     * If not in memory, checks DB for prior pairing history.
     */
    checkStatus(deviceId) {
        const code = this.activeDevices.get(deviceId);
        if (code) {
            const pairing = this.activeCodes.get(code);
            if (pairing) {
                if (Date.now() > pairing.expiresAt) {
                    this.activeCodes.delete(code);
                    this.activeDevices.delete(deviceId);
                }
                else if (pairing.paired && pairing.userId) {
                    // Pairing succeeded! Clear memory store and return success details
                    const userId = pairing.userId;
                    this.activeCodes.delete(code);
                    this.activeDevices.delete(deviceId);
                    return { paired: true, userId };
                }
                else {
                    return { paired: false };
                }
            }
        }
        // fallback: Check if database has it paired already
        try {
            const stmt = database_1.default.prepare('SELECT user_id FROM paired_devices WHERE device_id = ?');
            const row = stmt.all(deviceId)[0];
            if (row) {
                return { paired: true, userId: row.user_id };
            }
        }
        catch (err) {
            console.error(`[Pairing] DB check failed for device ${deviceId}:`, err);
        }
        return { paired: false };
    }
    /**
     * Unpairs/removes a device from the database
     */
    unpairDevice(deviceId) {
        try {
            const stmt = database_1.default.prepare('DELETE FROM paired_devices WHERE device_id = ?');
            stmt.run(deviceId);
            console.log(`[Pairing] Unpaired device ${deviceId}`);
            return true;
        }
        catch (err) {
            console.error(`[Pairing] Database error during unpairing:`, err);
            return false;
        }
    }
}
exports.pairingService = new PairingService();
