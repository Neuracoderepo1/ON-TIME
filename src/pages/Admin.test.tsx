import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';

vi.mock('../lib/api', () => ({
  isAdmin: vi.fn(),
  adminStats: vi.fn(),
  adminCreateRound: vi.fn(),
  adminRoundAction: vi.fn(),
  adminPendingRedemptions: vi.fn().mockResolvedValue([]),
  adminFulfil: vi.fn(),
  adminCancel: vi.fn(),
  adminAdjustCredits: vi.fn(),
  adminOpenFlags: vi.fn().mockResolvedValue([]),
  adminReviewFlag: vi.fn(),
  adminScanFlags: vi.fn(),
  listRounds: vi.fn().mockResolvedValue([]),
}));
import { isAdmin, adminStats } from '../lib/api';
import { Admin } from './Admin';

describe('Admin page gate', () => {
  it('shows Not authorised and never loads admin data for non-admins', async () => {
    vi.mocked(isAdmin).mockResolvedValue(false);
    render(<Admin />);
    expect(await screen.findByRole('alert')).toHaveTextContent(/not authorised/i);
    expect(adminStats).not.toHaveBeenCalled();
  });

  it('shows an error (not the admin UI) when the admin check itself fails', async () => {
    vi.mocked(isAdmin).mockRejectedValue(new Error('network down'));
    render(<Admin />);
    expect(await screen.findByRole('alert')).toHaveTextContent(/network down/);
  });

  it('renders the admin console for admins', async () => {
    vi.mocked(isAdmin).mockResolvedValue(true);
    vi.mocked(adminStats).mockResolvedValue({
      users: 3, check_ins: 5, credits_issued: 50, credits_redeemed: 0, redemptions_pending: 0,
      redemptions_pending_over_7d: 0, open_risk_flags: 0, ledger_mismatches: 0,
    });
    render(<Admin />);
    expect(await screen.findByRole('heading', { name: /administration/i })).toBeInTheDocument();
    expect(await screen.findByText('Members')).toBeInTheDocument();
  });
});
