import { expect, test } from '@playwright/test';

test('landing explains the loop and non-cash credits', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Be Online. Be There. Unlock More.');
  for (const step of ['Show up', 'Verify', 'Earn', 'Redeem']) await expect(page.getByRole('heading', { name: step })).toBeVisible();
  await expect(page.getByText(/no cash value/i).first()).toBeVisible();
  await expect(page.getByText('Illustrative example, not a real round')).toBeVisible();
  for (const l of ['Terms', 'Privacy', 'Eligibility', 'Reward conditions']) await expect(page.getByRole('link', { name: l }).first()).toBeVisible();
});

test('no horizontal overflow on any public page', async ({ page }) => {
  for (const path of ['/', '/signin', '/signup', '/terms', '/privacy', '/eligibility', '/reward-conditions']) {
    await page.goto(path);
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth);
    expect(overflow, path).toBeLessThanOrEqual(0);
  }
});

test('member routes redirect signed-out visitors to sign in', async ({ page }) => {
  for (const path of ['/app', '/app/rewards', '/app/admin']) {
    await page.goto(path);
    await expect(page).toHaveURL(/\/signin$/);
    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible();
  }
});

test('sign-up enforces age and terms before calling the server', async ({ page }) => {
  await page.goto('/signup');
  await page.getByLabel('Email').fill('person@example.com');
  await page.getByLabel('Password').fill('longenough1');
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByRole('alert')).toContainText('18');
  await page.getByLabel(/18 years old/).check();
  await page.getByRole('button', { name: 'Create account' }).click();
  await expect(page.getByRole('alert')).toContainText('Terms');
});

test('sign-in shows an error for bad credentials and stays signed out', async ({ page }) => {
  await page.goto('/signin');
  await page.getByLabel('Email').fill('nobody-e2e@example.invalid');
  await page.getByLabel('Password').fill('definitely-wrong-password');
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('alert')).toContainText(/incorrect|confirm/i);
  await expect(page).toHaveURL(/\/signin$/);
});

test('keyboard users can reach the skip link and main content', async ({ page }) => {
  await page.goto('/');
  await page.keyboard.press('Tab');
  await expect(page.getByRole('link', { name: 'Skip to content' })).toBeFocused();
});
