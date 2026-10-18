import { describe, expect, it, vi, beforeEach } from 'vitest';
import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { ErrorState, EmptyState, Skeleton } from './States';

vi.mock('../lib/api', () => ({ checkIn: vi.fn() }));
import { checkIn } from '../lib/api';
import { CheckInButton } from './CheckInButton';

const openRound = {
  participation_open_at: new Date(Date.now() - 60_000).toISOString(),
  participation_close_at: new Date(Date.now() + 3_600_000).toISOString(),
  cancelled_at: null,
};
const closedRound = {
  participation_open_at: new Date(Date.now() - 7_200_000).toISOString(),
  participation_close_at: new Date(Date.now() - 3_600_000).toISOString(),
  cancelled_at: null,
};

describe('state components', () => {
  it('renders loading, error with retry, and empty states accessibly', async () => {
    const retry = vi.fn();
    render(
      <>
        <Skeleton />
        <ErrorState message="Boom" onRetry={retry} />
        <EmptyState title="Nothing yet">Come back later</EmptyState>
      </>,
    );
    expect(screen.getByText('Loading…')).toBeInTheDocument();
    expect(screen.getByRole('alert')).toHaveTextContent('Boom');
    await userEvent.click(screen.getByRole('button', { name: /try again/i }));
    expect(retry).toHaveBeenCalledTimes(1);
    expect(screen.getByText('Nothing yet')).toBeInTheDocument();
  });
});

describe('CheckInButton', () => {
  beforeEach(() => vi.mocked(checkIn).mockReset());

  it('is hidden when the round is closed', () => {
    render(<CheckInButton roundId="r" round={closedRound} alreadyCheckedIn={false} onDone={() => {}} />);
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('shows a checked-in chip instead of the button when already checked in', () => {
    render(<CheckInButton roundId="r" round={openRound} alreadyCheckedIn onDone={() => {}} />);
    expect(screen.getByText(/checked in/i)).toBeInTheDocument();
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('submits once, reports server success, and refreshes', async () => {
    let resolve!: (v: unknown) => void;
    vi.mocked(checkIn).mockReturnValue(new Promise((r) => (resolve = r)) as never);
    const done = vi.fn();
    render(<CheckInButton roundId="r" round={openRound} alreadyCheckedIn={false} onDone={done} />);
    const btn = screen.getByRole('button', { name: /verify my presence/i });
    await userEvent.dblClick(btn);
    expect(checkIn).toHaveBeenCalledTimes(1);
    resolve({ ok: true, awarded: 10, bonus: 0, balance: 10, streak: 1, longest_streak: 1 });
    await waitFor(() => expect(screen.getByRole('status')).toHaveTextContent('+10 credits'));
    expect(done).toHaveBeenCalled();
  });

  it('shows a server rejection message and never claims success', async () => {
    vi.mocked(checkIn).mockResolvedValue({ ok: false, code: 'ALREADY_CHECKED_IN' });
    render(<CheckInButton roundId="r" round={openRound} alreadyCheckedIn={false} onDone={() => {}} />);
    await userEvent.click(screen.getByRole('button', { name: /verify/i }));
    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent(/already verified/i));
    expect(screen.queryByRole('status')).toBeNull();
  });
});
