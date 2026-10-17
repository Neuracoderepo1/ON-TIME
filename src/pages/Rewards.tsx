import { useState } from 'react';
import { getDashboard, listRewards, redeemReward, type RewardRow } from '../lib/api';
import { useAsync } from '../components/useAsync';
import { EmptyState, ErrorState, Skeleton } from '../components/States';
import { ApiError, messageForCode } from '../lib/errors';
import { redeemHint } from '../lib/eligibility';
import { clearRedemptionKey, getRedemptionKey } from '../lib/idempotency';
import { formatCredits } from '../lib/format';

interface Outcome {
  ok: boolean;
  text: string;
  ref?: string | null;
}

function RewardCard({ reward, balance, onChanged }: { reward: RewardRow; balance: number; onChanged: () => void }) {
  const [busy, setBusy] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [outcome, setOutcome] = useState<Outcome | null>(null);
  const hint = redeemHint(balance, reward);

  async function confirm() {
    if (busy) return;
    setBusy(true);
    setOutcome(null);
    const key = getRedemptionKey(reward.id); // same key for retries of this logical request
    try {
      const r = await redeemReward(reward.id, key);
      if (r.ok) {
        clearRedemptionKey(reward.id);
        setOutcome({
          ok: true,
          text: r.redemption.status === 'fulfilled' ? 'Redeemed. Your benefit is ready.' : 'Redeemed. Fulfilment is pending.',
          ref: r.redemption.fulfilment_ref,
        });
      } else {
        clearRedemptionKey(reward.id); // explicit rejection is definitive
        setOutcome({ ok: false, text: messageForCode(r.code) });
      }
      setConfirming(false);
      onChanged();
    } catch (e) {
      // Uncertain outcome: keep the key so a retry cannot double-spend.
      setOutcome({
        ok: false,
        text: `${e instanceof ApiError ? e.message : 'The request failed.'} If you retry, we will reuse the same request so you are not charged twice.`,
      });
    } finally {
      setBusy(false);
    }
  }

  return (
    <li className="panel">
      <div className="row between">
        <h2>{reward.title}</h2>
        <span className="chip">{reward.category}</span>
      </div>
      {reward.is_demo && <p className="chip">Demo reward</p>}
      <p>{reward.description}</p>
      {reward.partner && <p className="fine">Partner: {reward.partner.name}</p>}
      <p>
        <strong>{formatCredits(reward.cost)} credits</strong>
        {reward.stock !== null && <> · {reward.stock} left</>}
        {' · '}
        {reward.fulfilment_type === 'code_pool' ? 'Instant code' : 'Manual fulfilment'}
      </p>
      {reward.expires_at && <p className="fine">Expires {new Date(reward.expires_at).toLocaleDateString('en-GB')}</p>}

      {!confirming && (
        <button type="button" className="btn" disabled={!hint.allowed || busy} onClick={() => setConfirming(true)}>
          {hint.allowed ? 'Redeem' : hint.reason}
        </button>
      )}
      {confirming && (
        <div role="group" aria-label={`Confirm redemption of ${reward.title}`}>
          <p>
            Spend {formatCredits(reward.cost)} credits on this reward? {reward.instructions && <span className="fine">{reward.instructions}</span>}
          </p>
          <button type="button" className="btn" disabled={busy} onClick={confirm}>
            {busy ? 'Redeeming…' : 'Confirm'}
          </button>{' '}
          <button type="button" className="btn ghost" disabled={busy} onClick={() => setConfirming(false)}>
            Cancel
          </button>
        </div>
      )}
      {outcome && (
        <p role={outcome.ok ? 'status' : 'alert'} className={outcome.ok ? 'note ok' : 'note bad'}>
          {outcome.text} {outcome.ref && <code>{outcome.ref}</code>}
        </p>
      )}
    </li>
  );
}

export function Rewards() {
  const rewards = useAsync(listRewards);
  const dash = useAsync(getDashboard);
  const reload = () => {
    rewards.reload();
    dash.reload();
  };

  if ((rewards.loading && !rewards.data) || (dash.loading && !dash.data)) return <Skeleton lines={4} />;
  if (rewards.error || !rewards.data) return <ErrorState message={rewards.error ?? 'Could not load rewards.'} onRetry={rewards.reload} />;
  if (dash.error || !dash.data) return <ErrorState message={dash.error ?? 'Could not load your balance.'} onRetry={dash.reload} />;

  return (
    <div className="stack">
      <div className="row between">
        <h1>Rewards</h1>
        <p className="chip">Balance: {formatCredits(dash.data.balance)}</p>
      </div>
      {!dash.data.phone_verified && (
        <p className="note">
          Phone verification is not available yet, so redemptions are limited to one per week and new accounts wait 24 hours
          before their first redemption.
        </p>
      )}
      {rewards.data.length === 0 ? (
        <EmptyState title="No rewards available">Check back soon.</EmptyState>
      ) : (
        <ul className="cards">
          {rewards.data.map((r) => (
            <RewardCard key={r.id} reward={r} balance={dash.data!.balance} onChanged={reload} />
          ))}
        </ul>
      )}
    </div>
  );
}
