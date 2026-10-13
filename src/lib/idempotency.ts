const PREFIX = 'ontime:redeem-key:';

function store(): Storage | null {
  try {
    return window.sessionStorage;
  } catch {
    return null;
  }
}

const memory = new Map<string, string>();

/** One key per logical redemption attempt. Reused for retries until the outcome is definitive. */
export function getRedemptionKey(rewardId: string): string {
  const k = PREFIX + rewardId;
  const existing = store()?.getItem(k) ?? memory.get(k);
  if (existing) return existing;
  const fresh = `rd-${crypto.randomUUID()}`;
  try {
    store()?.setItem(k, fresh);
  } catch {
    /* fall back to memory */
  }
  memory.set(k, fresh);
  return fresh;
}

/** Call only once the server has given a definitive answer (success or an explicit rejection). */
export function clearRedemptionKey(rewardId: string): void {
  const k = PREFIX + rewardId;
  try {
    store()?.removeItem(k);
  } catch {
    /* ignore */
  }
  memory.delete(k);
}
