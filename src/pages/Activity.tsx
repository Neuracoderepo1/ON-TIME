import { getDashboard, listLedger, listMyCheckIns } from '../lib/api';
import { useAsync } from '../components/useAsync';
import { EmptyState, ErrorState, Skeleton } from '../components/States';
import { browserTimezone, formatDateTime, formatSignedCredits } from '../lib/format';

export function Activity() {
  const ledger = useAsync(() => listLedger(100));
  const checks = useAsync(listMyCheckIns);
  const dash = useAsync(getDashboard);

  if (ledger.loading && !ledger.data) return <Skeleton lines={5} />;
  if (ledger.error || !ledger.data) return <ErrorState message={ledger.error ?? 'Could not load activity.'} onRetry={ledger.reload} />;
  const tz = dash.data?.timezone ?? browserTimezone();

  return (
    <div className="stack">
      <h1>Activity</h1>
      <section className="panel" aria-labelledby="l-h">
        <h2 id="l-h">Credit ledger</h2>
        {ledger.data.length === 0 ? (
          <EmptyState title="No credit activity yet" />
        ) : (
          <ul className="list">
            {ledger.data.map((a) => (
              <li key={a.id}>
                <span>{a.description || a.type}</span>
                <span className={a.amount > 0 ? 'pos' : 'neg'}>{formatSignedCredits(a.amount)}</span>
                <time dateTime={a.created_at}>{formatDateTime(a.created_at, tz)}</time>
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="panel" aria-labelledby="c-h">
        <h2 id="c-h">Check-ins</h2>
        {checks.error ? (
          <ErrorState message={checks.error} onRetry={checks.reload} />
        ) : !checks.data || checks.data.length === 0 ? (
          <EmptyState title="No check-ins yet" />
        ) : (
          <ul className="list">
            {checks.data.map((c) => (
              <li key={c.round_id}>
                <span>Round check-in</span>
                <span />
                <time dateTime={c.checked_in_at}>{formatDateTime(c.checked_in_at, tz)}</time>
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="panel" aria-labelledby="r-h">
        <h2 id="r-h">Redemptions</h2>
        {!dash.data || dash.data.redemptions.length === 0 ? (
          <EmptyState title="No redemptions yet" />
        ) : (
          <ul className="list">
            {dash.data.redemptions.map((r) => (
              <li key={r.id}>
                <span>{r.title}</span>
                <span className="chip">{r.status}</span>
                <time dateTime={r.created_at}>{formatDateTime(r.created_at, tz)}</time>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
