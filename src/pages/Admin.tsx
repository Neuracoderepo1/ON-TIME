import { useState, type FormEvent } from 'react';
import {
  adminAdjustCredits,
  adminCancel,
  adminCreateRound,
  adminFulfil,
  adminOpenFlags,
  adminPendingRedemptions,
  adminReviewFlag,
  adminRoundAction,
  adminScanFlags,
  adminStats,
  isAdmin,
  listRounds,
} from '../lib/api';
import { useAsync } from '../components/useAsync';
import { EmptyState, ErrorState, Skeleton } from '../components/States';
import { browserTimezone, formatDateTime } from '../lib/format';
import { roundPhase } from '../lib/eligibility';

function useAction() {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  async function run(fn: () => Promise<unknown>, okText: string, after?: () => void) {
    if (busy) return;
    setBusy(true);
    setMsg(null);
    try {
      await fn();
      setMsg({ ok: true, text: okText });
      after?.();
    } catch (e) {
      setMsg({ ok: false, text: e instanceof Error ? e.message : 'Failed.' });
    } finally {
      setBusy(false);
    }
  }
  return { busy, msg, run };
}

function Msg({ msg }: { msg: { ok: boolean; text: string } | null }) {
  if (!msg) return null;
  return (
    <p role={msg.ok ? 'status' : 'alert'} className={msg.ok ? 'note ok' : 'note bad'}>
      {msg.text}
    </p>
  );
}

function StatsPanel() {
  const s = useAsync(adminStats);
  if (s.loading && !s.data) return <Skeleton lines={2} />;
  if (s.error || !s.data) return <ErrorState message={s.error ?? 'Could not load stats.'} onRetry={s.reload} />;
  const d = s.data;
  const items: [string, number][] = [
    ['Members', d.users],
    ['Check-ins', d.check_ins],
    ['Credits issued', d.credits_issued],
    ['Credits redeemed', d.credits_redeemed],
    ['Pending redemptions', d.redemptions_pending],
    ['Pending over 7 days', d.redemptions_pending_over_7d],
    ['Open risk flags', d.open_risk_flags],
    ['Ledger mismatches', d.ledger_mismatches],
  ];
  return (
    <div className="grid3">
      {items.map(([k, v]) => (
        <div key={k} className="panel stat">
          <span className="label">{k}</span>
          <strong>{v}</strong>
        </div>
      ))}
    </div>
  );
}

function RoundsPanel() {
  const rounds = useAsync(listRounds);
  const a = useAction();
  const [title, setTitle] = useState('');
  const [start, setStart] = useState('');
  const [open, setOpen] = useState('');
  const [close, setClose] = useState('');
  const [award, setAward] = useState(10);
  const tz = browserTimezone();

  function create(e: FormEvent) {
    e.preventDefault();
    if (!start || !open || !close) {
      return;
    }
    void a.run(
      () => adminCreateRound(title.trim() || 'ON-TIME Round', new Date(start).toISOString(), new Date(open).toISOString(), new Date(close).toISOString(), award),
      'Round created.',
      rounds.reload,
    );
  }

  return (
    <section className="panel stack" aria-labelledby="ar-h">
      <h2 id="ar-h">Rounds</h2>
      <form onSubmit={create} className="form">
        <label>Title<input value={title} maxLength={120} onChange={(e) => setTitle(e.target.value)} /></label>
        <label>Starts ({tz})<input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} required /></label>
        <label>Opens ({tz})<input type="datetime-local" value={open} onChange={(e) => setOpen(e.target.value)} required /></label>
        <label>Closes ({tz})<input type="datetime-local" value={close} onChange={(e) => setClose(e.target.value)} required /></label>
        <label>Credits awarded<input type="number" min={1} max={1000} value={award} onChange={(e) => setAward(Number(e.target.value))} required /></label>
        <button className="btn" disabled={a.busy}>Create round</button>
      </form>
      <Msg msg={a.msg} />
      {rounds.loading && !rounds.data ? (
        <Skeleton lines={2} />
      ) : rounds.error ? (
        <ErrorState message={rounds.error} onRetry={rounds.reload} />
      ) : !rounds.data || rounds.data.length === 0 ? (
        <EmptyState title="No rounds yet" />
      ) : (
        <ul className="list">
          {rounds.data.map((r) => {
            const phase = roundPhase(r, Date.now());
            return (
              <li key={r.id}>
                <span>
                  {r.title} <span className="chip">{phase}</span>
                  <br />
                  <span className="fine">{formatDateTime(r.participation_open_at, tz)} → {formatDateTime(r.participation_close_at, tz)}</span>
                </span>
                <span className="row">
                  {phase === 'scheduled' && <button type="button" className="btn ghost" disabled={a.busy} onClick={() => void a.run(() => adminRoundAction(r.id, 'open'), 'Round opened.', rounds.reload)}>Open now</button>}
                  {phase === 'open' && <button type="button" className="btn ghost" disabled={a.busy} onClick={() => void a.run(() => adminRoundAction(r.id, 'close'), 'Round closed.', rounds.reload)}>Close now</button>}
                  {phase !== 'cancelled' && <button type="button" className="btn ghost" disabled={a.busy} onClick={() => { if (window.confirm('Cancel this round?')) void a.run(() => adminRoundAction(r.id, 'cancel'), 'Round cancelled.', rounds.reload); }}>Cancel</button>}
                </span>
              </li>
            );
          })}
        </ul>
      )}
    </section>
  );
}

function RedemptionsPanel() {
  const list = useAsync(adminPendingRedemptions);
  const a = useAction();
  const [ref, setRef] = useState<Record<string, string>>({});
  return (
    <section className="panel stack" aria-labelledby="rd-h">
      <h2 id="rd-h">Pending redemptions</h2>
      <Msg msg={a.msg} />
      {list.loading && !list.data ? (
        <Skeleton lines={2} />
      ) : list.error ? (
        <ErrorState message={list.error} onRetry={list.reload} />
      ) : !list.data || list.data.length === 0 ? (
        <EmptyState title="Nothing pending" />
      ) : (
        <ul className="list">
          {list.data.map((r) => (
            <li key={r.id}>
              <span>
                {r.reward?.title ?? 'Reward'} · {r.cost} credits
                <br />
                <span className="fine">Member {r.user_id.slice(0, 8)}…</span>
              </span>
              <span className="row">
                <input aria-label="Fulfilment reference" placeholder="Fulfilment reference" value={ref[r.id] ?? ''} onChange={(e) => setRef({ ...ref, [r.id]: e.target.value })} />
                <button type="button" className="btn" disabled={a.busy || !(ref[r.id] ?? '').trim()} onClick={() => void a.run(() => adminFulfil(r.id, (ref[r.id] ?? '').trim()), 'Marked fulfilled.', list.reload)}>Fulfil</button>
                <button type="button" className="btn ghost" disabled={a.busy} onClick={() => { const reason = window.prompt('Reason for cancelling (credits are refunded)?'); if (reason) void a.run(() => adminCancel(r.id, reason), 'Cancelled and refunded.', list.reload); }}>Cancel and refund</button>
              </span>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function RiskPanel() {
  const flags = useAsync(adminOpenFlags);
  const a = useAction();
  return (
    <section className="panel stack" aria-labelledby="rf-h">
      <h2 id="rf-h">Risk review</h2>
      <button type="button" className="btn ghost" disabled={a.busy} onClick={() => void a.run(async () => { const n = await adminScanFlags(); return n; }, 'Scan complete.', flags.reload)}>Run risk scan</button>
      <Msg msg={a.msg} />
      {flags.loading && !flags.data ? (
        <Skeleton lines={2} />
      ) : flags.error ? (
        <ErrorState message={flags.error} onRetry={flags.reload} />
      ) : !flags.data || flags.data.length === 0 ? (
        <EmptyState title="No open flags" />
      ) : (
        <ul className="list">
          {flags.data.map((f) => (
            <li key={f.id}>
              <span>{f.kind} · {f.flagged_on}<br /><span className="fine">Member {f.user_id?.slice(0, 8) ?? '—'}…</span></span>
              <button type="button" className="btn ghost" disabled={a.busy} onClick={() => { const note = window.prompt('Review note?'); if (note) void a.run(() => adminReviewFlag(f.id, note), 'Marked reviewed.', flags.reload); }}>Mark reviewed</button>
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

function CreditsPanel() {
  const a = useAction();
  const [user, setUser] = useState('');
  const [amount, setAmount] = useState(0);
  const [reason, setReason] = useState('');
  function submit(e: FormEvent) {
    e.preventDefault();
    void a.run(() => adminAdjustCredits(user.trim(), amount, reason.trim()), 'Adjustment recorded in the ledger.');
  }
  return (
    <section className="panel" aria-labelledby="ac-h">
      <h2 id="ac-h">Credit adjustment</h2>
      <form onSubmit={submit} className="form">
        <label>Member ID<input value={user} onChange={(e) => setUser(e.target.value)} required /></label>
        <label>Amount (negative to deduct)<input type="number" value={amount} onChange={(e) => setAmount(Number(e.target.value))} required /></label>
        <label>Reason (required, audited)<input value={reason} onChange={(e) => setReason(e.target.value)} required /></label>
        <button className="btn" disabled={a.busy || amount === 0 || !reason.trim() || !user.trim()}>Apply adjustment</button>
      </form>
      <Msg msg={a.msg} />
    </section>
  );
}

export function Admin() {
  const check = useAsync(isAdmin);
  if (check.loading && check.data === null) return <Skeleton lines={3} />;
  if (check.error) return <ErrorState message={check.error} onRetry={check.reload} />;
  // The UI gate is a convenience only; every operation below is authorised again by the database.
  if (!check.data) {
    return (
      <div className="panel" role="alert">
        <h1>Not authorised</h1>
        <p>This area is only for ON-TIME administrators.</p>
      </div>
    );
  }
  return (
    <div className="stack">
      <h1>Administration</h1>
      <StatsPanel />
      <RoundsPanel />
      <RedemptionsPanel />
      <RiskPanel />
      <CreditsPanel />
    </div>
  );
}
