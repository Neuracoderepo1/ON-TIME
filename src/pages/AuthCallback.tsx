import { useEffect, useState } from 'react';
import { Link, Navigate } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { Skeleton } from '../components/States';

function callbackError(): string | null {
  const q = new URLSearchParams(window.location.search);
  const h = new URLSearchParams(window.location.hash.replace(/^#/, ''));
  return q.get('error_description') ?? h.get('error_description');
}

export function AuthCallback() {
  const { session, loading } = useAuth();
  const [timedOut, setTimedOut] = useState(false);
  const err = callbackError();

  useEffect(() => {
    const t = setTimeout(() => setTimedOut(true), 8000);
    return () => clearTimeout(t);
  }, []);

  if (session) return <Navigate to="/app" replace />;
  if (err || (timedOut && !loading)) {
    return (
      <div className="container narrow">
        <h1>We could not confirm that link</h1>
        <div role="alert" className="panel error">
          <p>The link may have expired or already been used. You can sign in if your email is already confirmed.</p>
          <Link className="btn" to="/signin">
            Go to sign in
          </Link>
        </div>
      </div>
    );
  }
  return (
    <div className="container narrow">
      <Skeleton lines={2} />
    </div>
  );
}
