import { useEffect, useState } from 'react';

/** Current time in ms, re-rendering the caller every `intervalMs` so time-derived UI never goes stale. */
export function useNow(intervalMs = 1000): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(t);
  }, [intervalMs]);
  return now;
}
