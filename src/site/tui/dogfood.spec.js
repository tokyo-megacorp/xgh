// @ts-check
const { test, expect } = require('@playwright/test');
const path = require('path');

const TUI_URL = 'file://' + path.resolve(__dirname, 'out/claude-tui.html');
const LANDING_URL = 'file://' + path.resolve(__dirname, 'out/index.html');

test.describe('TUI Demo Engine — Dogfood', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(TUI_URL);
    await page.waitForTimeout(500);
  });

  // ── Smoke: page loads and renders ────────────────────────────────────────────
  test('renders window chrome', async ({ page }) => {
    await expect(page.locator('.window')).toBeVisible();
    await expect(page.locator('.title-bar')).toBeVisible();
    await expect(page.locator('.cc-header')).toBeVisible();
    await expect(page.locator('.status-bar')).toBeVisible();
  });

  test('populates shell identity from config', async ({ page }) => {
    await expect(page.locator('#cc-name')).toHaveText('Lossless Claude');
    await expect(page.locator('#cc-version')).toHaveText('v2.0.0');
    const pathEl = page.locator('#cc-path');
    await expect(pathEl).toHaveText('claude plugin install xgh@extreme-go-horse');
    await expect(pathEl).toHaveAttribute('href', '#install');
  });

  test('picks a random model string', async ({ page }) => {
    const model = await page.locator('#cc-model').textContent();
    const expected = ['medium effort', 'high effort', 'max effort', 'low effort', 'xhigh effort'];
    expect(expected).toContain(model.trim());
  });

  test('status bar shows left text', async ({ page }) => {
    await expect(page.locator('#status-left')).toHaveText('? for shortcuts · hold Space to speak');
  });

  // ── CSS variables applied ────────────────────────────────────────────────────
  test('CSS variables are applied from theme', async ({ page }) => {
    const bg = await page.evaluate(() =>
      getComputedStyle(document.documentElement).getPropertyValue('--bg').trim()
    );
    expect(bg).toBe('#0d0e17');
  });

  // ── Demo autoplay starts ────────────────────────────────────────────────────
  test('demo autoplay starts and types a command', async ({ page }) => {
    // Wait for typing to begin (the first demo types /xgh-brief)
    await page.waitForFunction(() => {
      const input = document.getElementById('input-text');
      return input && input.textContent.length > 0;
    }, { timeout: 5000 });
    const text = await page.locator('#input-text').textContent();
    expect(text.length).toBeGreaterThan(0);
  });

  // ── Interactive mode: click to focus ─────────────────────────────────────────
  test('click on input row enters interactive mode', async ({ page }) => {
    // Wait for autoplay to start, then click to interrupt
    await page.waitForTimeout(1000);
    await page.locator('#input-row').click();
    await page.waitForTimeout(300);
    // Cursor should become visible
    await expect(page.locator('#cursor')).toBeVisible();
  });

  // ── Interactive mode: type anywhere ──────────────────────────────────────────
  test('typing anywhere enters interactive mode and seeds first char', async ({ page }) => {
    // Wait for autoplay to start, then type to interrupt
    await page.waitForTimeout(1000);
    await page.keyboard.press('h');
    await page.waitForTimeout(500);
    const text = await page.locator('#input-text').textContent();
    expect(text).toContain('h');
    await expect(page.locator('#cursor')).toBeVisible();
  });

  // ── Autocomplete ─────────────────────────────────────────────────────────────
  test('typing / shows autocomplete with commands', async ({ page }) => {
    await page.keyboard.press('/');
    await page.waitForTimeout(300);
    const ac = page.locator('#autocomplete');
    await expect(ac).toHaveClass(/visible/);
    // Should have rows for known commands
    const rows = ac.locator('.ac-row');
    const count = await rows.count();
    expect(count).toBeGreaterThan(0);
  });

  test('autocomplete filters as user types', async ({ page }) => {
    await page.keyboard.type('/ins', { delay: 50 });
    await page.waitForTimeout(200);
    const rows = page.locator('#autocomplete .ac-row');
    const count = await rows.count();
    expect(count).toBeGreaterThanOrEqual(1);
    const firstCmd = await rows.first().locator('.ac-cmd').textContent();
    expect(firstCmd).toContain('/install');
  });

  // ── Command execution: /help ─────────────────────────────────────────────────
  test('/help lists all commands', async ({ page }) => {
    await page.keyboard.type('/help', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('/install');
    expect(text).toContain('/about');
    expect(text).toContain('/color');
    expect(text).toContain('/help');
  });

  // ── Command execution: /install ──────────────────────────────────────────────
  test('/install shows install instructions', async ({ page }) => {
    await page.keyboard.type('/install', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('Install xgh');
    expect(text).toContain('claude plugin install');
  });

  // ── Command execution: /about ────────────────────────────────────────────────
  test('/about shows about info', async ({ page }) => {
    await page.keyboard.type('/about', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('xgh');
  });

  // ── Command execution: /color ────────────────────────────────────────────────
  test('/color changes accent and shows confirmation', async ({ page }) => {
    await page.keyboard.type('/color pink', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('pink');
  });

  // ── Command execution: /rename ───────────────────────────────────────────────
  test('/rename updates divider label', async ({ page }) => {
    await page.keyboard.type('/rename my-label', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const label = await page.locator('#input-label').textContent();
    expect(label).toContain('my-label');
  });

  // ── Unknown command ──────────────────────────────────────────────────────────
  test('unknown command shows error message', async ({ page }) => {
    await page.keyboard.type('/nonexistent', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    const conv = page.locator('#conv');
    const text = await conv.textContent();
    expect(text).toContain('Unknown command');
    expect(text).toContain('/help');
  });

  // ── ESC exits interactive mode ───────────────────────────────────────────────
  test('Escape exits interactive mode', async ({ page }) => {
    // Wait for autoplay to start, then enter interactive
    await page.waitForTimeout(1000);
    await page.keyboard.press('h');
    await page.waitForTimeout(500);
    await expect(page.locator('#cursor')).toBeVisible();

    // Exit
    await page.keyboard.press('Escape');
    await page.waitForTimeout(300);
    await expect(page.locator('#cursor')).toBeHidden();
  });

  // ── Race condition: ESC + immediate re-entry ─────────────────────────────────
  test('ESC then immediate re-entry does not restart autoplay', async ({ page }) => {
    // Wait for autoplay to start, then enter interactive
    await page.waitForTimeout(1000);
    await page.keyboard.press('h');
    await page.waitForTimeout(500);

    // Exit
    await page.keyboard.press('Escape');
    await page.waitForTimeout(100);

    // Immediately re-enter
    await page.keyboard.press('x');
    await page.waitForTimeout(100);

    // Should still be in interactive mode, cursor visible
    await expect(page.locator('#cursor')).toBeVisible();
    const text = await page.locator('#input-text').textContent();
    expect(text).toContain('x');

    // Wait past the 600ms debounce
    await page.waitForTimeout(700);

    // Should STILL be interactive — autoplay should NOT have fired
    await expect(page.locator('#cursor')).toBeVisible();
  });

  // ── Demo scene renders tool blocks ───────────────────────────────────────────
  test('demo scene renders skill badges and tool blocks', async ({ page }) => {
    // Let the first demo play for a few seconds
    await page.waitForTimeout(4000);
    const conv = page.locator('#conv');
    // Should have at least one skill badge
    const badges = conv.locator('.skill-badge');
    await expect(badges.first()).toBeVisible({ timeout: 8000 });
    // Should have at least one tool block
    const tools = conv.locator('.tool-block');
    await expect(tools.first()).toBeVisible({ timeout: 3000 });
  });

  // ── Screenshot: full autoplay cycle ──────────────────────────────────────────
  test('screenshot: demo in progress', async ({ page }) => {
    await page.waitForTimeout(6000);
    await page.screenshot({ path: 'src/site/tui/out/screenshot-demo.png', fullPage: true });
  });

  test('screenshot: interactive /help', async ({ page }) => {
    await page.keyboard.type('/help', { delay: 30 });
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    await page.screenshot({ path: 'src/site/tui/out/screenshot-help.png', fullPage: true });
  });

  test('screenshot: autocomplete', async ({ page }) => {
    await page.keyboard.type('/co', { delay: 50 });
    await page.waitForTimeout(300);
    await page.screenshot({ path: 'src/site/tui/out/screenshot-autocomplete.png', fullPage: true });
  });
});

// ═══════════════════════════════════════════════════════════════════════════════
// Landing Page Tests
// ═══════════════════════════════════════════════════════════════════════════════

test.describe('Landing Page — Layout & Interactions', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(LANDING_URL);
    await page.waitForTimeout(500);
  });

  // ── Layout: sections stacked vertically ──────────────────────────────────────
  test('hero, features, install, footer are stacked vertically', async ({ page }) => {
    const hero = await page.locator('.hero').boundingBox();
    const features = await page.locator('.features').boundingBox();
    const install = await page.locator('.install').boundingBox();
    const footer = await page.locator('.footer').boundingBox();

    expect(hero).not.toBeNull();
    expect(features).not.toBeNull();
    expect(install).not.toBeNull();
    expect(footer).not.toBeNull();

    // Each section should start below the previous one
    expect(features.y).toBeGreaterThan(hero.y + hero.height - 10);
    expect(install.y).toBeGreaterThan(features.y);
    expect(footer.y).toBeGreaterThan(install.y);
  });

  test('TUI is inside hero and not wider than 900px', async ({ page }) => {
    const tui = await page.locator('.hero-tui').boundingBox();
    expect(tui).not.toBeNull();
    expect(tui.width).toBeLessThanOrEqual(920); // 900 + padding tolerance
  });

  test('feature cards are not beside the TUI', async ({ page }) => {
    const tui = await page.locator('.hero-tui').boundingBox();
    const grid = await page.locator('.features-grid').boundingBox();

    // The features grid should start below the hero section entirely
    expect(grid.y).toBeGreaterThan(tui.y + tui.height - 10);
    // The grid should not overlap horizontally in a weird way — it should be centered
    expect(grid.x).toBeGreaterThanOrEqual(0);
  });

  // ── Feature cards ──────────────────────────────────────────────────────────────
  test('renders 6 feature cards', async ({ page }) => {
    const cards = page.locator('.feature-card');
    await expect(cards).toHaveCount(6);
  });

  test('feature cards have icon, headline, and description', async ({ page }) => {
    const first = page.locator('.feature-card').first();
    await expect(first.locator('.feature-icon')).not.toBeEmpty();
    await expect(first.locator('.feature-headline')).not.toBeEmpty();
    await expect(first.locator('.feature-desc')).not.toBeEmpty();
  });

  test('feature cards become visible on scroll', async ({ page }) => {
    // Cards start invisible (opacity: 0)
    const firstCard = page.locator('.feature-card').first();
    const initialOpacity = await firstCard.evaluate(el =>
      getComputedStyle(el).opacity
    );
    expect(initialOpacity).toBe('0');

    // Scroll to features section
    await page.locator('.features').scrollIntoViewIfNeeded();
    await page.waitForTimeout(600);

    // After scrolling, cards should have the visible class
    await expect(firstCard).toHaveClass(/visible/);
  });

  // ── Install section ────────────────────────────────────────────────────────────
  test('install section has steps', async ({ page }) => {
    const steps = page.locator('.install-step');
    const count = await steps.count();
    expect(count).toBeGreaterThan(0);
  });

  // ── Footer ─────────────────────────────────────────────────────────────────────
  test('footer has GitHub and npm links', async ({ page }) => {
    const footer = page.locator('.footer');
    await expect(footer.locator('a', { hasText: 'GitHub' })).toBeVisible();
    await expect(footer.locator('a', { hasText: 'npm' })).toBeVisible();
  });

  // ── TUI embed interactions ─────────────────────────────────────────────────────
  test('TUI inside landing page autoplays demos', async ({ page }) => {
    await page.waitForFunction(() => {
      const input = document.getElementById('input-text');
      return input && input.textContent.length > 0;
    }, { timeout: 5000 });
    const text = await page.locator('#input-text').textContent();
    expect(text.length).toBeGreaterThan(0);
  });

  test('TUI inside landing page accepts keyboard interaction', async ({ page }) => {
    await page.waitForTimeout(1000);
    await page.keyboard.press('/');
    await page.waitForTimeout(300);
    const ac = page.locator('#autocomplete');
    await expect(ac).toHaveClass(/visible/);
  });

  // ── Copy-to-clipboard install badge ────────────────────────────────────────────
  test('clicking install badge shows "Copied!" feedback', async ({ page }) => {
    // Grant clipboard permissions
    await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
    const pathEl = page.locator('#cc-path');
    await pathEl.click();
    await page.waitForTimeout(300);
    await expect(pathEl).toHaveText('Copied!');
    // Reverts after timeout
    await page.waitForTimeout(1800);
    await expect(pathEl).toHaveText('claude plugin install xgh@extreme-go-horse');
  });

  // ── Screenshots ────────────────────────────────────────────────────────────────
  test('screenshot: landing page hero', async ({ page }) => {
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'out/screenshot-landing-hero.png', fullPage: false });
  });

  test('screenshot: landing page features', async ({ page }) => {
    await page.locator('.features').scrollIntoViewIfNeeded();
    await page.waitForTimeout(800);
    await page.screenshot({ path: 'out/screenshot-landing-features.png', fullPage: false });
  });

  test('screenshot: landing page full scroll', async ({ page }) => {
    // Let TUI autoplay for a moment
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'out/screenshot-landing-full.png', fullPage: true });
  });
});
