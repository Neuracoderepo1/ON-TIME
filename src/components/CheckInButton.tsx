import { useEffect, useRef, useState } from 'react';
import { checkIn } from '../lib/api';
import { ApiError, messageForCode } from '../lib/errors';
import { canShowCheckIn, type RoundLike } from '../lib/eligibility';

interface Props {
  roundId: string;
  round: RoundLike;
  alreadyCheckedIn: boolean;
  onDone: () => void;
}

export function CheckInButton({ roundId, round, alreadyCheckedIn, onDone }: Props) {
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<{ ok: boolean; text: string } | null>(null);
  const inFlight = useRef(false);
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  async function submit() {
    if (inFlight.current) return; // prevents accidental double submission
    inFlight.current = true;
    setBusy(true);
    setMsg(null);
    try {
      const r = await checkIn(roundId);
      if (r.ok) {
        setMsg({
          ok: true,
          text: `Verified. +${r.awarded} credits${r.bonus ? ` and a +${r.bonus} streak bonus` : ''}.`,
        });
      } else {
        setMsg({ ok: false, text: messageForCode(r.code) });
      }
      onDone(); // always re-read authoritative state
    } catch (e) {
      setMsg({ ok: false, text: e instanceof ApiError ? e.message : 'Check-in failed.' });
      onDone();
    } finally {
      inFlight.current = false;
      setBusy(false);
    }
  }

  const show = canShowCheckIn(round, now, alreadyCheckedIn, false);
  return (
    <div>
      {alreadyCheckedIn && <p className="chip ok">You’re checked in</p>}
      {(show || busy) && (
        <button type="button" className="btn big" disabled={busy} onClick={submit}>
          {busy ? 'Verifying…' : 'Verify my presence'}
        </button>
      )}
      {msg && (
        <p role={msg.ok ? 'status' : 'alert'} className={msg.ok ? 'note ok' : 'note bad'}>
          {msg.text}
        </p>
      )}
    </div>
  );
}
