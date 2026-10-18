import { Link } from 'react-router-dom';

const STEPS = [
  { n: '1', t: 'Show up', d: 'Join a scheduled round when it opens.' },
  { n: '2', t: 'Verify', d: 'Confirm your presence inside the eligible window.' },
  { n: '3', t: 'Earn', d: 'Collect ON-TIME Credits and build a consistency streak.' },
  { n: '4', t: 'Redeem', d: 'Exchange credits for partner benefits, subject to stock and terms.' },
];

export function Landing() {
  return (
    <>
      <section className="hero container">
        <p className="eyebrow">Presence-based loyalty</p>
        <h1>Be Online. Be There. Unlock More.</h1>
        <p className="lead">
          ON-TIME rewards members who show up. Verify your presence during a scheduled round, earn loyalty credits, and
          redeem them for benefits from partners.
        </p>
        <div className="cta-row">
          <Link className="btn big" to="/signup">
            Create account
          </Link>
          <Link className="btn ghost big" to="/signin">
            Sign in
          </Link>
        </div>
        <p className="fine">Free to join. 18+ only. No entry fees, wagers or cash prizes.</p>
      </section>

      <section id="how" className="container section">
        <h2>How it works</h2>
        <ol className="steps">
          {STEPS.map((s) => (
            <li key={s.n} className="panel">
              <span className="step-n" aria-hidden="true">
                {s.n}
              </span>
              <h3>{s.t}</h3>
              <p>{s.d}</p>
            </li>
          ))}
        </ol>
      </section>

      <section id="credits" className="container section">
        <h2>About ON-TIME Credits</h2>
        <div className="panel">
          <ul className="plain">
            <li>Credits are loyalty points, not money. They have no cash value.</li>
            <li>They cannot be bought, withdrawn, sold or transferred to another member.</li>
            <li>Participation is always free. Nothing is wagered and nothing is a prize draw.</li>
            <li>Rewards are loyalty benefits offered by partners, subject to availability and the reward’s conditions.</li>
            <li>We never promise a financial return.</li>
          </ul>
          <p className="fine">
            Read the <Link to="/reward-conditions">reward conditions</Link> and <Link to="/eligibility">eligibility rules</Link>.
          </p>
        </div>
      </section>

      <section className="container section">
        <h2>What a round looks like</h2>
        <div className="panel illustrative" aria-label="Illustrative example">
          <p className="chip">Illustrative example, not a real round</p>
          <h3>Example round</h3>
          <p>Opens at a set time, stays open for a set window, and pays a fixed number of credits if you verify in time.</p>
          <p className="fine">Real rounds, times and credit amounts appear in your dashboard after you sign in.</p>
        </div>
      </section>
    </>
  );
}
