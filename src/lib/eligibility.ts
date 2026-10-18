export interface RoundLike {
  participation_open_at: string;
  participation_close_at: string;
  cancelled_at?: string | null;
}

export type RoundPhase = 'cancelled' | 'scheduled' | 'open' | 'closed';

/** Usability-only phase. The database remains authoritative for eligibility and timing. */
export function roundPhase(round: RoundLike, nowMs: number): RoundPhase {
  if (round.cancelled_at) return 'cancelled';
  if (nowMs < Date.parse(round.participation_open_at)) return 'scheduled';
  if (nowMs < Date.parse(round.participation_close_at)) return 'open';
  return 'closed';
}

export function canShowCheckIn(round: RoundLike, nowMs: number, alreadyCheckedIn: boolean, busy: boolean): boolean {
  return !busy && !alreadyCheckedIn && roundPhase(round, nowMs) === 'open';
}

export interface RedeemHint {
  allowed: boolean;
  reason?: string;
}

/** Hints only; the server enforces balance, stock, holds and caps. */
export function redeemHint(balance: number, reward: { cost: number; stock: number | null }): RedeemHint {
  if (reward.stock !== null && reward.stock <= 0) return { allowed: false, reason: 'Out of stock' };
  if (balance < reward.cost) return { allowed: false, reason: `Need ${reward.cost - balance} more credits` };
  return { allowed: true };
}
