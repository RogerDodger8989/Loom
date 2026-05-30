declare class PairingService {
    private activeCodes;
    private activeDevices;
    /**
     * Generates a random alphanumeric code of a specific length
     */
    private generateCode;
    /**
     * Requests a new pairing code for a specific Device ID
     */
    requestPairing(deviceId: string): {
        code: string;
        deviceId: string;
        expiresAt: number;
    };
    /**
     * Confirms a pairing request from an authenticated administrator / user screen.
     * Links the code to the confirming User's ID and persists it.
     */
    confirmPairing(code: string, userId: string, deviceName?: string): boolean;
    /**
     * Checks the pairing status of a device.
     * If in-memory paired, returns JWT token info, and removes from memory.
     * If not in memory, checks DB for prior pairing history.
     */
    checkStatus(deviceId: string): {
        paired: boolean;
        userId?: string;
    };
    /**
     * Unpairs/removes a device from the database
     */
    unpairDevice(deviceId: string): boolean;
}
export declare const pairingService: PairingService;
export {};
