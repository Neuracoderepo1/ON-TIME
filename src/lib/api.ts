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
