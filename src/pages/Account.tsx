import { useEffect, useState, type FormEvent } from 'react';
import { getDashboard, updateProfile } from '../lib/api';
import { useAsync } from '../components/useAsync';
import { ErrorState, Skeleton } from '../components/States';
import { useAuth } from '../auth/AuthProvider';

function timezones(): string[] {
  try {
    const fn = (Intl as unknown as { supportedValuesOf?: (k: string) => string[] }).supportedValuesOf;
    const list = fn ? fn('timeZone') : [];
    return list.includes('UTC') ? list : ['UTC', ...list];
  } catch {
    return ['UTC'];
  }
}

export function Account() {
  const { user } = useAuth();
  const dash = useAsync(getDashboard);
  const [name, setName] = useState('');
  const [tz, setTz] = useState('UTC');
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);

  useEffect(() => {
    if (dash.data) {
      setName(dash.data.display_name ?? '');
      setTz(dash.data.timezone);
    }
  }, [dash.data]);

  if (dash.loading && !dash.data) return <Skeleton lines={4} />;
  if (dash.error || !dash.data) return <ErrorState message={dash.error ?? 'Could not load your account.'} onRetry={dash.reload} />;

  async function save(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setBusy(true);
    setMsg(null);
    try {
      await updateProfile(name.trim(), tz);
      setMsg({ ok: true, text: 'Saved.' });
      dash.reload();
    } catch (err) {
      setMsg({ ok: false, text: err instanceof Error ? err.message : 'Could not save.' });
    } finally {
      setBusy(false);
    }
  }

  const zones = timezones();
  return (
    <div className="stack narrow">
      <h1>Account</h1>
      <form onSubmit={save} className="panel form">
        <p>
          Signed in as <strong>{user?.email}</strong>
        </p>
        <label>
          Display name
          <input value={name} maxLength={60} onChange={(e) => setName(e.target.value)} />
        </label>
        <label>
          Timezone
          <select value={tz} onChange={(e) => setTz(e.target.value)}>
            {(zones.includes(tz) ? zones : [tz, ...zones]).map((z) => (
              <option key={z} value={z}>
                {z}
              </option>
            ))}
          </select>
        </label>
        <p className="fine">Your timezone sets the calendar day used for daily limits and streaks.</p>
        {msg && (
          <p role={msg.ok ? 'status' : 'alert'} className={msg.ok ? 'note ok' : 'note bad'}>
            {msg.text}
          </p>
        )}
        <button className="btn" disabled={busy}>
          {busy ? 'Saving…' : 'Save changes'}
        </button>
      </form>
      <p className="fine">Phone verification: {dash.data.phone_verified ? 'verified' : 'not available yet'}.</p>
    </div>
  );
}
