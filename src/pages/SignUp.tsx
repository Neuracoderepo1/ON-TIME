import { useState, type FormEvent } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';
import { browserTimezone } from '../lib/format';

export interface SignUpFields {
  email: string;
  password: string;
  age: boolean;
  consent: boolean;
}

export function validateSignUp(f: SignUpFields): string | null {
  if (!/^\S+@\S+\.\S+$/.test(f.email.trim())) return 'Enter a valid email address.';
  if (f.password.length < 8) return 'Use a password of at least 8 characters.';
  if (!f.age) return 'You must confirm that you are 18 or older.';
  if (!f.consent) return 'You must accept the Terms and Privacy Policy.';
  return null;
}

export function SignUp() {
  const { session } = useAuth();
  const [f, setF] = useState<SignUpFields>({ email: '', password: '', age: false, consent: false });
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  if (session) return <Navigate to="/app" replace />;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    const v = validateSignUp(f);
    if (v) {
      setError(v);
      return;
    }
    setError(null);
    setBusy(true);
    // The database trigger re-checks these flags and rejects the signup if they are missing.
    const { error: err } = await supabase.auth.signUp({
      email: f.email.trim(),
      password: f.password,
      options: {
        emailRedirectTo: `${window.location.origin}/auth/callback`,
        data: { age_confirmed: true, consent: true, display_name: name.trim(), timezone: browserTimezone() },
      },
    });
    setBusy(false);
    if (err) {
      setError(/already/i.test(err.message) ? 'An account with this email may already exist. Try signing in.' : 'We could not create your account. Please check your details and try again.');
      return;
    }
    setSent(true);
  }

  if (sent) {
    return (
      <div className="container narrow">
        <h1>Check your email</h1>
        <div className="panel" role="status">
          <p>
            We sent a confirmation link to <strong>{f.email.trim()}</strong>. Open it to activate your account, then sign in.
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="container narrow">
      <h1>Create your account</h1>
      <form onSubmit={submit} noValidate className="panel form">
        <label>
          Display name (optional)
          <input value={name} maxLength={60} onChange={(e) => setName(e.target.value)} autoComplete="nickname" />
        </label>
        <label>
          Email
          <input type="email" autoComplete="email" value={f.email} onChange={(e) => setF({ ...f, email: e.target.value })} required />
        </label>
        <label>
          Password
          <input
            type="password"
            autoComplete="new-password"
            value={f.password}
            onChange={(e) => setF({ ...f, password: e.target.value })}
            required
            minLength={8}
          />
        </label>
        <label className="check">
          <input type="checkbox" checked={f.age} onChange={(e) => setF({ ...f, age: e.target.checked })} />
          <span>I confirm that I am 18 years old or older.</span>
        </label>
        <label className="check">
          <input type="checkbox" checked={f.consent} onChange={(e) => setF({ ...f, consent: e.target.checked })} />
          <span>
            I accept the <Link to="/terms">Terms</Link> and <Link to="/privacy">Privacy Policy</Link>.
          </span>
        </label>
        {error && (
          <p role="alert" className="note bad">
            {error}
          </p>
        )}
        <button className="btn big" disabled={busy}>
          {busy ? 'Creating…' : 'Create account'}
        </button>
        <p className="fine">
          Already a member? <Link to="/signin">Sign in</Link>
        </p>
      </form>
    </div>
  );
}
