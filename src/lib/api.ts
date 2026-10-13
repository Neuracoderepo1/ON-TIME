import { z } from 'zod';
import { supabase } from './supabase';
import { ApiError, messageForCode } from './errors';

/* Contracts below were read from the deployed function bodies (see docs/BACKEND_CONTRACTS.md). */

const Dashboard = z.object({
  balance: z.number(),
  streak: z.number(),
  longest_streak: z.number(),
  timezone: z.string(),
  display_name: z.string().nullable(),
  phone_verified: z.boolean(),
  rounds_participated: z.number(),
  activity: z.array(
    z.object({ id: z.string(), amount: z.number(), type: z.string(), description: z.string(), created_at: z.string() }),
  ),
  redemptions: z.array(
    z.object({
      id: z.string(),
      status: z.enum(['pending', 'fulfilled', 'cancelled']),
      cost: z.number(),
      fulfilment_ref: z.string().nullable(),
      created_at: z.string(),
      title: z.string(),
      is_demo: z.boolean(),
    }),
  ),
});
export type DashboardData = z.infer<typeof Dashboard>;

const Round = z.object({
  id: z.string(),
  title: z.string(),
  start_at: z.string(),
  participation_open_at: z.string(),
  participation_close_at: z.string(),
  credit_award: z.number(),
  cancelled_at: z.string().nullable().optional(),
});
export type RoundRow = z.infer<typeof Round>;

const NextRound = Round.extend({ status: z.string(), server_now: z.string() }).nullable();
export type NextRound = z.infer<typeof NextRound>;

const Reward = z.object({
  id: z.string(),
  title: z.string(),
  description: z.string(),
  category: z.string(),
  cost: z.number(),
  stock: z.number().nullable(),
  instructions: z.string(),
  expires_at: z.string().nullable(),
  fulfilment_type: z.enum(['code_pool', 'manual']),
  is_demo: z.boolean(),
  partner: z.object({ name: z.string(), description: z.string() }).nullable(),
});
export type RewardRow = z.infer<typeof Reward>;

const CheckInResult = z.union([
  z.object({
    ok: z.literal(true),
    awarded: z.number(),
    bonus: z.number(),
    balance: z.number(),
    streak: z.number(),
    longest_streak: z.number(),
  }),
  z.object({ ok: z.literal(false), code: z.string() }),
]);
export type CheckInResultT = z.infer<typeof CheckInResult>;

const RedeemResult = z.union([
  z.object({
    ok: z.literal(true),
    replay: z.boolean(),
    redemption: z.object({
      id: z.string(),
      status: z.enum(['pending', 'fulfilled', 'cancelled']),
      cost: z.number(),
      fulfilment_ref: z.string().nullable(),
    }),
  }),
  z.object({ ok: z.literal(false), code: z.string() }).passthrough(),
]);
export type RedeemResultT = z.infer<typeof RedeemResult>;

const SimpleResult = z.object({ ok: z.boolean(), code: z.string().optional() });

function parse<T>(schema: z.ZodType<T>, data: unknown, what: string): T {
  const r = schema.safeParse(data);
  if (!r.success) throw new ApiError(`Unexpected response from the server (${what}).`);
  return r.data;
}

function fail(error: { message: string; code?: string }): never {
  if (error.code === 'PGRST301' || /jwt/i.test(error.message)) throw new ApiError(messageForCode('NOT_AUTHENTICATED'), 'NOT_AUTHENTICATED');
  throw new ApiError('We could not reach the server. Please try again.', error.code);
}

export async function getDashboard(): Promise<DashboardData> {
  const { data, error } = await supabase.rpc('my_dashboard');
  if (error) fail(error);
  if (data === null) throw new ApiError(messageForCode('NOT_AUTHENTICATED'), 'NOT_AUTHENTICATED');
  return parse(Dashboard, data, 'dashboard');
}

export async function getNextRound(): Promise<NextRound> {
  const { data, error } = await supabase.rpc('next_round_info');
  if (error) fail(error);
  return parse(NextRound, data ?? null, 'next round');
}

export async function listRounds(): Promise<RoundRow[]> {
  const { data, error } = await supabase
    .from('rounds')
    .select('id,title,start_at,participation_open_at,participation_close_at,credit_award,cancelled_at')
    .order('start_at', { ascending: false })
    .limit(50);
  if (error) fail(error);
  return parse(z.array(Round), data ?? [], 'rounds');
}

export async function listMyCheckIns(): Promise<{ round_id: string; checked_in_at: string }[]> {
  const { data, error } = await supabase
    .from('check_ins')
    .select('round_id,checked_in_at')
    .order('checked_in_at', { ascending: false })
    .limit(200);
  if (error) fail(error);
  return parse(z.array(z.object({ round_id: z.string(), checked_in_at: z.string() })), data ?? [], 'check-ins');
}

export async function listRewards(): Promise<RewardRow[]> {
  const { data, error } = await supabase
    .from('rewards')
    .select(
      'id,title,description,category,cost,stock,instructions,expires_at,fulfilment_type,is_demo,partner:partners(name,description)',
    )
    .order('cost', { ascending: true });
  if (error) fail(error);
  return parse(z.array(Reward), data ?? [], 'rewards');
}

export async function listLedger(limit = 100): Promise<DashboardData['activity']> {
  const { data, error } = await supabase
    .from('credit_ledger')
    .select('id,amount,type,description,created_at')
    .order('created_at', { ascending: false })
    .limit(limit);
  if (error) fail(error);
  return parse(Dashboard.shape.activity, data ?? [], 'ledger');
}

export async function checkIn(roundId: string): Promise<CheckInResultT> {
  const { data, error } = await supabase.rpc('check_in', { p_round_id: roundId });
  if (error) fail(error);
  return parse(CheckInResult, data, 'check-in');
}

export async function redeemReward(rewardId: string, idempotencyKey: string): Promise<RedeemResultT> {
  const { data, error } = await supabase.rpc('redeem_reward', {
    p_reward_id: rewardId,
    p_idempotency_key: idempotencyKey,
  });
  if (error) fail(error);
  return parse(RedeemResult, data, 'redemption');
}

export async function updateProfile(displayName: string, timezone: string): Promise<void> {
  const { data, error } = await supabase.rpc('update_profile', { p_display_name: displayName, p_timezone: timezone });
  if (error) fail(error);
  const r = parse(SimpleResult, data, 'profile update');
  if (!r.ok) throw new ApiError(messageForCode(r.code), r.code);
}

/* ---------------- Admin (every call is authorised server-side by require_admin()) ---------------- */

export async function isAdmin(): Promise<boolean> {
  const { data, error } = await supabase.rpc('is_admin');
  if (error) fail(error);
  return data === true;
}

function adminFail(error: { message: string; code?: string }): never {
  if (error.code === '42501' || /FORBIDDEN/.test(error.message)) throw new ApiError('You are not authorised to do that.', 'FORBIDDEN');
  const known = error.message.match(/^[A-Z_]{4,}$/);
  throw new ApiError(known ? `Request rejected: ${known[0]}` : 'The request could not be completed.', error.code);
}

const Stats = z.object({
  users: z.number(),
  check_ins: z.number(),
  credits_issued: z.number(),
  credits_redeemed: z.number(),
  redemptions_pending: z.number(),
  redemptions_pending_over_7d: z.number(),
  open_risk_flags: z.number(),
  ledger_mismatches: z.number(),
});
export type AdminStats = z.infer<typeof Stats>;

export async function adminStats(): Promise<AdminStats> {
  const { data, error } = await supabase.rpc('admin_stats');
  if (error) adminFail(error);
  return parse(Stats, data, 'admin stats');
}

export async function adminCreateRound(title: string, startAt: string, openAt: string, closeAt: string, award: number): Promise<void> {
  const { error } = await supabase.rpc('admin_upsert_round', {
    p_id: null as unknown as string,
    p_title: title,
    p_start: startAt,
    p_open: openAt,
    p_close: closeAt,
    p_award: award,
  });
  if (error) adminFail(error);
}

export async function adminRoundAction(id: string, action: 'open' | 'close' | 'cancel'): Promise<void> {
  const { error } = await supabase.rpc('admin_round_action', { p_id: id, p_action: action });
  if (error) adminFail(error);
}

const PendingRedemption = z.object({
  id: z.string(),
  user_id: z.string(),
  cost: z.number(),
  status: z.string(),
  created_at: z.string(),
  reward: z.object({ title: z.string() }).nullable(),
});
export type PendingRedemptionRow = z.infer<typeof PendingRedemption>;

export async function adminPendingRedemptions(): Promise<PendingRedemptionRow[]> {
  const { data, error } = await supabase
    .from('redemptions')
    .select('id,user_id,cost,status,created_at,reward:rewards(title)')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })
    .limit(100);
  if (error) fail(error);
  return parse(z.array(PendingRedemption), data ?? [], 'pending redemptions');
}

export async function adminFulfil(id: string, ref: string): Promise<void> {
  const { error } = await supabase.rpc('admin_fulfil_redemption', { p_id: id, p_ref: ref });
  if (error) adminFail(error);
}

export async function adminCancel(id: string, reason: string): Promise<void> {
  const { error } = await supabase.rpc('admin_cancel_redemption', { p_id: id, p_reason: reason });
  if (error) adminFail(error);
}

export async function adminAdjustCredits(userId: string, amount: number, reason: string): Promise<void> {
  const { data, error } = await supabase.rpc('admin_adjust_credits', { p_user: userId, p_amount: amount, p_reason: reason });
  if (error) adminFail(error);
  const r = parse(SimpleResult, data, 'credit adjustment');
  if (!r.ok) throw new ApiError(`Request rejected: ${r.code ?? 'UNKNOWN'}`, r.code);
}

const Flag = z.object({
  id: z.string(),
  user_id: z.string().nullable(),
  kind: z.string(),
  detail: z.unknown(),
  flagged_on: z.string(),
});
export type FlagRow = z.infer<typeof Flag>;

export async function adminOpenFlags(): Promise<FlagRow[]> {
  const { data, error } = await supabase
    .from('risk_flags')
    .select('id,user_id,kind,detail,flagged_on')
    .is('reviewed_at', null)
    .order('created_at', { ascending: false })
    .limit(100);
  if (error) fail(error);
  return parse(z.array(Flag), data ?? [], 'risk flags');
}

export async function adminReviewFlag(id: string, note: string): Promise<void> {
  const { error } = await supabase.rpc('admin_review_flag', { p_id: id, p_note: note });
  if (error) adminFail(error);
}

export async function adminScanFlags(): Promise<number> {
  const { data, error } = await supabase.rpc('admin_scan_risk_flags');
  if (error) adminFail(error);
  return typeof data === 'number' ? data : 0;
}
