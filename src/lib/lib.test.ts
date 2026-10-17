import { describe, expect, it, beforeEach } from 'vitest';
import { canShowCheckIn, redeemHint, roundPhase } from './eligibility';
import { formatCountdown, formatCredits, formatDateTime, formatSignedCredits } from './format';
import { messageForCode } from './errors';
import { clearRedemptionKey, getRedemptionKey } from './idempotency';
import { validateSignUp } from '../pages/SignUp';
import { signInMessage } from '../pages/SignIn';

const round = {
  participation_open_at: '2026-10-13T10:00:00Z',
  participation_close_at: '2026-10-13T11:00:00Z',
  cancelled_at: null,
};
const t = (s: string) => Date.parse(s);

describe('format', () => {
  it('formats credits and signed credits', () => {
    expect(formatCredits(1234)).toBe('1,234');
    expect(formatSignedCredits(10)).toBe('+10');
    expect(formatSignedCredits(-60)).toBe('−60');
  });
  it('formats times in the member timezone', () => {
    expect(formatDateTime('2026-10-13T10:00:00Z', 'Africa/Accra')).toContain('10:00');
    expect(formatDateTime('2026-10-13T10:00:00Z', 'Asia/Tokyo')).toContain('19:00');
  });
  it('falls back safely on bad input', () => {
    expect(formatDateTime('nope', 'UTC')).toBe('—');
    expect(formatDateTime('2026-10-13T10:00:00Z', 'Not/AZone')).toContain('10:00');
  });
  it('formats countdowns', () => {
    expect(formatCountdown(-5)).toBe('0s');
    expect(formatCountdown(65_000)).toBe('1m 5s');
    expect(formatCountdown(3_700_000)).toBe('1h 1m');
  });
});

describe('eligibility', () => {
  it('derives round phases', () => {
    expect(roundPhase(round, t('2026-10-13T09:59:59Z'))).toBe('scheduled');
    expect(roundPhase(round, t('2026-10-13T10:00:00Z'))).toBe('open');
    expect(roundPhase(round, t('2026-10-13T11:00:00Z'))).toBe('closed');
    expect(roundPhase({ ...round, cancelled_at: 'x' }, t('2026-10-13T10:30:00Z'))).toBe('cancelled');
  });
  it('shows check-in only when open, not yet checked in, not busy', () => {
    const open = t('2026-10-13T10:30:00Z');
    expect(canShowCheckIn(round, open, false, false)).toBe(true);
    expect(canShowCheckIn(round, open, true, false)).toBe(false);
    expect(canShowCheckIn(round, open, false, true)).toBe(false);
    expect(canShowCheckIn(round, t('2026-10-13T12:00:00Z'), false, false)).toBe(false);
  });
  it('gives redemption hints', () => {
    expect(redeemHint(100, { cost: 60, stock: null }).allowed).toBe(true);
    expect(redeemHint(10, { cost: 60, stock: null })).toEqual({ allowed: false, reason: 'Need 50 more credits' });
    expect(redeemHint(100, { cost: 60, stock: 0 }).reason).toBe('Out of stock');
  });
});

describe('errors', () => {
  it('maps known codes and falls back for unknown ones', () => {
    expect(messageForCode('INSUFFICIENT_CREDITS')).toMatch(/enough/);
    expect(messageForCode('AGE_CONFIRMATION_REQUIRED')).toMatch(/18/);
    expect(messageForCode('CONSENT_REQUIRED')).toMatch(/Terms/);
    expect(messageForCode('???')).toMatch(/Something went wrong/);
    expect(messageForCode(undefined)).toMatch(/Something went wrong/);
  });
});

describe('idempotency keys', () => {
  beforeEach(() => sessionStorage.clear());
  it('reuses the key until cleared, then issues a new one', () => {
    const a = getRedemptionKey('r1');
    expect(getRedemptionKey('r1')).toBe(a);
    expect(a.length).toBeGreaterThanOrEqual(8);
    expect(getRedemptionKey('r2')).not.toBe(a);
    clearRedemptionKey('r1');
    expect(getRedemptionKey('r1')).not.toBe(a);
  });
});

describe('sign-up validation', () => {
  const ok = { email: 'a@b.co', password: 'longenough', age: true, consent: true };
  it('accepts valid input', () => expect(validateSignUp(ok)).toBeNull());
  it('rejects each missing requirement', () => {
    expect(validateSignUp({ ...ok, email: 'bad' })).toMatch(/email/);
    expect(validateSignUp({ ...ok, password: 'short' })).toMatch(/8 characters/);
    expect(validateSignUp({ ...ok, age: false })).toMatch(/18/);
    expect(validateSignUp({ ...ok, consent: false })).toMatch(/Terms/);
  });
});

describe('sign-in error mapping', () => {
  it('distinguishes bad credentials, unconfirmed email, rate limits and outages', () => {
    expect(signInMessage({ code: 'invalid_credentials', message: 'x' })).toBe('Incorrect email or password.');
    expect(signInMessage({ code: 'email_not_confirmed', message: 'x' })).toMatch(/confirm your email/);
    expect(signInMessage({ status: 429, message: 'x' })).toMatch(/Too many/);
    // a network failure must never be reported as a wrong password
    expect(signInMessage({ status: 0, message: 'Failed to fetch' })).toMatch(/could not sign you in/);
    expect(signInMessage({ message: 'Failed to fetch' })).not.toMatch(/Incorrect/);
  });
});
