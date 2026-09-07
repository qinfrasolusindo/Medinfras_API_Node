/**
 * Every log line is prefixed with an ISO-8601 timestamp:
 *   [2026-09-07T09:15:03.123Z] [INFO] Medinfras API listening on ...
 *
 * This matters beyond readability: deploy/windows/medinfras.ps1's
 * `-Action Logs -From ... -To ...` searches log files by parsing this exact
 * prefix. If you swap this out for a different logging library later, keep
 * a similar `[ISO-TIMESTAMP] [LEVEL]` prefix (or update the regex in
 * medinfras.ps1 to match your new format).
 */

type Level = 'info' | 'warn' | 'error';

function write(level: Level, message: string, meta?: unknown): void {
  const line = `[${new Date().toISOString()}] [${level.toUpperCase()}] ${message}`;
  const target = level === 'error' ? console.error : console.log;
  if (meta !== undefined) {
    target(line, meta);
  } else {
    target(line);
  }
}

export const logger = {
  info: (message: string, meta?: unknown) => write('info', message, meta),
  warn: (message: string, meta?: unknown) => write('warn', message, meta),
  error: (message: string, meta?: unknown) => write('error', message, meta),
};
