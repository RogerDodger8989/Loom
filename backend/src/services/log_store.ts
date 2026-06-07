export type LogLevel = 'info' | 'warn' | 'error' | 'debug';

export interface LogEntry {
  id: number;
  time: number;
  level: LogLevel;
  msg: string;
}

const MAX_ENTRIES = 1000;
let _seq = 0;
const _buffer: LogEntry[] = [];

export function addLog(level: LogLevel, msg: string): void {
  _buffer.push({ id: ++_seq, time: Date.now(), level, msg: String(msg).trim() });
  if (_buffer.length > MAX_ENTRIES) _buffer.shift();
}

export function getEntries(sinceId?: number): LogEntry[] {
  if (sinceId === undefined) return [..._buffer];
  return _buffer.filter(e => e.id > sinceId);
}

export function getAllAsText(): string {
  return _buffer
    .map(e => `[${new Date(e.time).toISOString()}] [${e.level.toUpperCase().padEnd(5)}] ${e.msg}`)
    .join('\n');
}
