export class ApiError extends Error {
  constructor(message: string, public readonly code?: string) {
    super(message);
    this.name = 'ApiError';
  }
}

const MESSAGES: Record<string, string> = {
  NOT_AUTHENTICATED: 'Your session has expired. Please sign in again.',
  RATE_LIMITED: 'Too many attempts. Please wait a minute and try again.',
  EMAIL_NOT_VERIFIED: 'Please confirm your email address first. Check your inbox for the confirmation link.',
  AGE_CONFIRMATION_REQUIRED: 'You must confirm that you are 18 or older before you can take part. Please contact support if this is wrong.',
  CONSENT_REQUIRED: 'You must accept the Terms and Privacy Notice before you can take part. Please contact support if this is wrong.',
  NO_PROFILE: 'We could not find your member profile. Please sign out and in again.',
  ROUND_NOT_FOUND: 'That round no longer exists.',
  ROUND_NOT_OPEN: 'This round has not opened yet.',
  ROUND_CLOSED: 'This round is closed.',
  ALREADY_CHECKED_IN: 'You have already verified your presence for this round.',
  DAILY_CAP_REACHED: 'You have reached today’s credit limit. Come back tomorrow.',
  BAD_IDEMPOTENCY_KEY: 'The request could not be processed. Please try again.',
  PHONE_REQUIRED: 'Phone verification is required for redemptions.',
  WEEKLY_LIMIT: 'You have reached the weekly redemption limit while phone verification is unavailable.',
  NEW_ACCOUNT_HOLD: 'New accounts have a short waiting period before the first redemption.',
  REWARD_UNAVAILABLE: 'This reward is no longer available.',
  OUT_OF_STOCK: 'This reward is out of stock.',
  INSUFFICIENT_CREDITS: 'You do not have enough ON-TIME Credits for this reward.',
  INVALID_TIMEZONE: 'That timezone is not recognised.',
};

export function messageForCode(code: string | undefined): string {
  return (code && MESSAGES[code]) || 'Something went wrong. Please try again.';
}
