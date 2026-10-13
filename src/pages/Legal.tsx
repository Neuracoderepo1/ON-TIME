import type { ReactNode } from 'react';

function Page({ title, children }: { title: string; children: ReactNode }) {
  return (
    <div className="container narrow prose">
      <h1>{title}</h1>
      {children}
      <p className="fine">Summary of how ON-TIME works. This text should be reviewed by qualified counsel before public launch.</p>
    </div>
  );
}

export function Terms() {
  return (
    <Page title="Terms of use">
      <p>ON-TIME is a free loyalty programme. Members verify their presence in scheduled rounds and earn ON-TIME Credits.</p>
      <ul>
        <li>You must be 18 or older and provide accurate information.</li>
        <li>Participation is free. There are no entry fees, wagers, prize draws or cash prizes.</li>
        <li>Credits are non-cash, non-withdrawable, non-transferable and cannot be purchased.</li>
        <li>We may cancel rounds, adjust credits for errors, and suspend accounts for abuse or automated activity.</li>
        <li>Rewards are subject to stock, expiry and partner terms.</li>
      </ul>
    </Page>
  );
}

export function Privacy() {
  return (
    <Page title="Privacy">
      <p>We collect the information needed to run the programme.</p>
      <ul>
        <li>Account data: email, optional display name, country and timezone, and your age and terms confirmations.</li>
        <li>Activity data: check-ins, credit ledger entries and redemptions.</li>
        <li>Abuse-prevention signals: a one-way hash of your network address, used for rate limiting and risk review.</li>
        <li>You can request an export or deletion of your data from your account.</li>
      </ul>
    </Page>
  );
}

export function Eligibility() {
  return (
    <Page title="Eligibility">
      <ul>
        <li>Members must be 18 or older. You confirm this at sign-up and we record the confirmation on your profile.</li>
        <li>You must confirm your email address before you can check in or redeem.</li>
        <li>New accounts have a 24-hour wait before their first redemption.</li>
        <li>Phone verification is not available yet. Until it is, redemptions are limited to one per week.</li>
        <li>Daily credit limits apply, based on your timezone’s calendar day.</li>
      </ul>
    </Page>
  );
}

export function RewardConditions() {
  return (
    <Page title="Reward conditions">
      <ul>
        <li>Rewards are loyalty benefits, not money, and credits cannot be exchanged for cash.</li>
        <li>Availability is limited and may change. Some rewards expire.</li>
        <li>Each reward may carry its own partner terms and usage instructions.</li>
        <li>Demo rewards are placeholders used to test the programme and are labelled as such.</li>
        <li>Cancelled redemptions are refunded as credits.</li>
      </ul>
    </Page>
  );
}

export function NotFound() {
  return (
    <div className="container narrow">
      <h1>Page not found</h1>
      <p>
        <a href="/">Back to home</a>
      </p>
    </div>
  );
}
