import { useState, type FormEvent } from 'react';
import { Link, Navigate, useLocation, useNavigate } from 'react-router-dom';
import { supabase } from '../lib/supabase';
import { useAuth } from '../auth/AuthProvider';

export function SignIn() {
  const { session } = useAuth();
  const nav = useNavigate();
  const loc = useLocation();
  const from = (loc.state as { from?: string } | null)?.from ?? '/app';
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (session) return <Navigate to="/app" replace />;

  async function submit(e: FormEvent) {
    e.preventDefault();
    if (busy) return;
    setError(null);
    if (!email.trim() || !password) {
      setError('Enter your email and password.');
      return;
    }
    setBusy(true);
    const { error: err } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (err) {
      setError(/confirm/i.test(err.message) ? 'Please confirm your email first. Check your inbox.' : 'Incorrect email or password.');
      return;
    }
    nav(from, { replace: true });
  }

  return (
    <div className="container narrow">
      <h1>Sign in</h1>
      <form onSubmit={submit} noValidate className="panel form">
        <label>
          Email
          <input type="email" autoComplete="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label>
          Password
          <input
            type="password"
            autoComplete="current-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            required
          />
        </label>
        {error && (
          <p role="alert" className="note bad">
            {error}
          </p>
        )}
        <button className="btn big" disabled={busy}>
          {busy ? 'Signing in…' : 'Sign in'}
        </button>
        <p className="fine">
          New here? <Link to="/signup">Create an account</Link>
        </p>
      </form>
    </div>
  );
}
