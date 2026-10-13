import { getDashboard, listMyCheckIns, listRounds } from '../lib/api';
import { useAsync } from '../components/useAsync';
import { EmptyState, ErrorState, Skeleton } from '../components/States';
import { CheckInButton } from '../components/CheckInButton';
import { roundPhase } from '../lib/eligibility';
import { browserTimezone, formatDateTime } from '../lib/format';

export function Rounds() {
  const rounds = useAsync(listRounds);
  const mine = useAsync(listMyCheckIns);
  const dash = useAsync(getDashboard);
  const reload = () => {
    rounds.reload();
    mine.reload();
    dash.reload();
  };

  if (rounds.loading && !rounds.data) return <Skeleton lines={4} />;
  if (rounds.error || !rounds.data) return <ErrorState message={rounds.error ?? 'Could not load rounds.'} onRetry={rounds.reload} />;

  const tz = dash.data?.timezone ?? browserTimezone();
  const checked = new Set((mine.data ?? []).map((c) => c.round_id));
  const now = Date.now();

  return (
    <div className="stack">
      <h1>Rounds</h1>
      {rounds.data.length === 0 ? (
        <EmptyState title="No rounds scheduled">Rounds will appear here once they are published.</EmptyState>
      ) : (
        <ul className="cards">
          {rounds.data.map((r) => {
            const phase = roundPhase(r, now);
            const done = checked.has(r.id);
            return (
              <li key={r.id} className="panel">
                <div className="row between">
                  <h2>{r.title}</h2>
                  <span className={`chip ${phase === 'open' ? 'ok' : ''}`}>{done ? 'participated' : phase}</span>
                </div>
                <p>
                  Opens {formatDateTime(r.participation_open_at, tz)}
                  <br />
                  Closes {formatDateTime(r.participation_close_at, tz)}
                </p>
                <p>Earns {r.credit_award} credits</p>
                <CheckInButton roundId={r.id} round={r} alreadyCheckedIn={done} onDone={reload} />
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
