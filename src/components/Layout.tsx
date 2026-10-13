import { useState } from 'react';
import { Link, NavLink, Outlet } from 'react-router-dom';
import { useAuth } from '../auth/AuthProvider';
import { isAdmin } from '../lib/api';
import { useAsync } from './useAsync';

export function Logo() {
  return (
    <span className="logo">
      <span className="logo-dot" aria-hidden="true" />
      ON-TIME
    </span>
  );
}

export function PublicLayout() {
  const { user, signOut } = useAuth();
  const [open, setOpen] = useState(false);
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <header className="topbar">
        <Link to="/" aria-label="ON-TIME home">
          <Logo />
        </Link>
        <button
          type="button"
          className="btn ghost menu-btn"
          aria-expanded={open}
          aria-controls="pubnav"
          onClick={() => setOpen(!open)}
        >
          Menu
        </button>
        <nav id="pubnav" aria-label="Primary" className={open ? 'nav open' : 'nav'} onClick={() => setOpen(false)}>
          <a href="/#how">How it works</a>
          <a href="/#credits">About credits</a>
          {user ? (
            <>
              <Link to="/app">Dashboard</Link>
              <button type="button" className="btn ghost" onClick={signOut}>
                Sign out
              </button>
            </>
          ) : (
            <>
              <Link to="/signin">Sign in</Link>
              <Link className="btn" to="/signup">
                Create account
              </Link>
            </>
          )}
        </nav>
      </header>
      <main id="main">
        <Outlet />
      </main>
      <footer className="footer">
        <Logo />
        <nav aria-label="Legal">
          <Link to="/terms">Terms</Link>
          <Link to="/privacy">Privacy</Link>
          <Link to="/eligibility">Eligibility</Link>
          <Link to="/reward-conditions">Reward conditions</Link>
        </nav>
        <p>
          ON-TIME Credits are non-cash loyalty credits. They have no cash value and cannot be bought, sold, withdrawn or
          transferred.
        </p>
      </footer>
    </>
  );
}

export function MemberLayout() {
  const { signOut } = useAuth();
  const [open, setOpen] = useState(false);
  const admin = useAsync(isAdmin); // navigation hint only; the database authorises every admin call
  return (
    <>
      <a className="skip" href="#main">
        Skip to content
      </a>
      <header className="topbar">
        <Link to="/app" aria-label="ON-TIME dashboard">
          <Logo />
        </Link>
        <button
          type="button"
          className="btn ghost menu-btn"
          aria-expanded={open}
          aria-controls="mbrnav"
          onClick={() => setOpen(!open)}
        >
          Menu
        </button>
        <nav id="mbrnav" aria-label="Member" className={open ? 'nav open' : 'nav'} onClick={() => setOpen(false)}>
          <NavLink to="/app" end>
            Dashboard
          </NavLink>
          <NavLink to="/app/rounds">Rounds</NavLink>
          <NavLink to="/app/rewards">Rewards</NavLink>
          <NavLink to="/app/activity">Activity</NavLink>
          <NavLink to="/app/account">Account</NavLink>
          {admin.data === true && <NavLink to="/app/admin">Admin</NavLink>}
          <button type="button" className="btn ghost" onClick={signOut}>
            Sign out
          </button>
        </nav>
      </header>
      <main id="main" className="member">
        <Outlet />
      </main>
    </>
  );
}
