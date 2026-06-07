export type ScanEventType =
  | 'scan_start'
  | 'file_found'
  | 'item_added'
  | 'item_updated'
  | 'item_skipped'
  | 'scan_complete'
  | 'scan_error';

export interface ScanEvent {
  id: number;
  time: number;
  type: ScanEventType;
  message: string;
  mediaType?: string;
}

const MAX_EVENTS = 500;
let _seq = 0;
const _events: ScanEvent[] = [];

export function emitScanEvent(type: ScanEventType, message: string, mediaType?: string): void {
  _events.push({ id: ++_seq, time: Date.now(), type, message, mediaType });
  if (_events.length > MAX_EVENTS) _events.shift();
}

export function getScanEvents(sinceId?: number): ScanEvent[] {
  if (sinceId === undefined) return [..._events];
  return _events.filter(e => e.id > sinceId);
}

export function clearScanEvents(): void {
  _events.length = 0;
}
