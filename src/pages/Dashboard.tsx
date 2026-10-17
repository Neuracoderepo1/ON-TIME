import { Link } from 'react-router-dom';
import { getDashboard, getNextRound, listMyCheckIns } from '../lib/api';
import { useAsync } from '../components/useAsync';
import { EmptyState, ErrorState, Skeleton } from '../components/States';
import { CheckInButton } from '../components/CheckInButton';
import { formatCredits, formatDateTime, formatSignedCredits } from '../lib/format';

export function Dashboard() {
  const dash = useAsync(getDashboard);
  const next = useAsync(getNextRound);
  const mine = useAsync(listMyCheckIns);

  const refresh = () => {
    dash.reload();
    next.reload();
    mine.reload();
  };

  if (dash.loading && !dash.data) return <Skeleton lines={5} />;
  if (dash.error || !dash.data) return <ErrorState message={dash.error ?? 'Could not load your dashboard.'} onRetry={dash.reload} />;
  const d = dash.data;
  const tz = d.timezone;
  const checked = new Set((mine.data ?? []).map((c) => c.round_id));

  return (
    <div className="stack">
      <div className="row between">
        <h1>{d.display_name ? `Welcome, ${d.display_name}` : 'Welcome'}</h1>
        <button type="button" className="btn ghost" onClick={refresh}>
          Refresh
        </button>
      </div>

      <div className="grid3">
        <div className="panel stat">
          <span className="label">Available credits</span>
          <strong data-testid="balance">{formatCredits(d.balance)}</strong>
        </div>
        <div className="panel stat">
          <span className="label">Current streak</span>
          <strong>{d.streak} {d.streak === 1 ? 'day' : 'days'}</strong>
        </div>
        <div className="panel stat">
          <span className="label">Longest streak</span>
          <strong>{d.longest_streak} {d.longest_streak === 1 ? 'day' : 'days'}</strong>
        </div>
      </div>

      <section className="panel" aria-labelledby="next-h">
        <h2 id="next-h">Next round</h2>
        {next.loading && !next.data && next.data !== null ? (
          <Skeleton lines={2} />
        ) : next.error ? (
          <ErrorState message={next.error} onRetry={next.reload} />
        ) : next.data ? (
          <>
            <h3>{next.data.title}</h3>
            <p>
              Opens {formatDateTime(next.data.participation_open_at, tz)} · closes {formatDateTime(next.data.participation_close_at, tz)}
            </p>
            <p>Earns {next.data.credit_award} credits · Status: {next.data.status}</p>
            <CheckInButton
              roundId={next.data.id}
              round={next.data}
              alreadyCheckedIn={checked.has(next.data.id)}
              onDone={refresh}
            />
          </>
        ) : (
          <EmptyState title="No upcoming rounds">New rounds will appear here when they are scheduled.</EmptyState>
        )}
      </section>

      <section className="panel" aria-labelledby="act-h">
        <div className="row between">
          <h2 id="act-h">Recent activity</h2>
          <Link to="/app/activity">View all</Link>
        </div>
        {d.activity.length === 0 ? (
          <EmptyState title="No activity yet">Verify your presence in a round to earn your first credits.</EmptyState>
        ) : (
          <ul className="list">
            {d.activity.slice(0, 5).map((a) => (
              <li key={a.id}>
                <span>{a.description || a.type}</span>
                <span className={a.amount > 0 ? 'pos' : 'neg'}>{formatSignedCredits(a.amount)}</span>
                <time dateTime={a.created_at}>{formatDateTime(a.created_at, tz)}</time>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="panel" aria-labelledby="red-h">
        <h2 id="red-h">Your redemptions</h2>
        {d.redemptions.length === 0 ? (
          <EmptyState title="No redemptions yet">
            Browse the <Link to="/app/rewards">rewards catalogue</Link> when you have credits.
          </EmptyState>
        ) : (
          <ul className="list">
            {d.redemptions.slice(0, 5).map((r) => (
              <li key={r.id}>
                <span>{r.title}{r.is_demo ? ' (demo)' : ''}</span>
                <span className={`chip ${r.status === 'cancelled' ? 'bad' : 'ok'}`}>{r.status}</span>
                <time dateTime={r.created_at}>{formatDateTime(r.created_at, tz)}</time>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
