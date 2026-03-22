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
    await expect(page.locator('#cc-name')).toHaveText('eXtreme Go Horse');
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

test.describe('Landing Page — Story Sections', () => {

  test.beforeEach(async ({ page }) => {
    await page.goto(LANDING_URL);
    await page.waitForTimeout(500);
  });

  // ── Layout ─────────────────────────────────────────────────────────────────────
  test('hero and 6 story sections are stacked vertically', async ({ page }) => {
    const hero = await page.locator('.hero').boundingBox();
    const stories = page.locator('.story');
    await expect(stories).toHaveCount(6);

    const first = await stories.first().boundingBox();
    expect(first.y).toBeGreaterThan(hero.y + hero.height - 10);
  });

  test('each story section has headline and description', async ({ page }) => {
    const sections = page.locator('.story');
    const count = await sections.count();
    for (let i = 0; i < count; i++) {
      const s = sections.nth(i);
      await expect(s.locator('.story-headline')).not.toBeEmpty();
      await expect(s.locator('.story-desc')).not.toBeEmpty();
    }
  });

  test('story sections start invisible and reveal on scroll', async ({ page }) => {
    const memory = page.locator('#s-memory');
    // Should not have in-view class initially (it's below fold)
    // Scroll to it
    await memory.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(600);
    await expect(memory).toHaveClass(/in-view/);
  });

  // ── Memory section ─────────────────────────────────────────────────────────────
  test('memory section has two mini terminals', async ({ page }) => {
    const terms = page.locator('#s-memory .mini-term');
    await expect(terms).toHaveCount(2);
  });

  test('memory section plays typewriter on scroll', async ({ page }) => {
    await page.locator('#s-memory').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    // Wait for typewriter to complete
    await page.waitForTimeout(4000);
    const typed1 = await page.locator('.mem-typed[data-idx="1"]').textContent();
    expect(typed1).toContain('lcm_store');
    const output1 = page.locator('.mini-output[data-idx="1"]');
    await expect(output1).toHaveClass(/show/);
  });

  // ── Briefing section ───────────────────────────────────────────────────────────
  test('briefing section has 3 source cards and summary', async ({ page }) => {
    const cards = page.locator('#s-briefing .brief-card');
    await expect(cards).toHaveCount(3);
    await expect(page.locator('#s-briefing .brief-summary')).toBeAttached();
  });

  test('briefing cards animate in on scroll', async ({ page }) => {
    await page.locator('#s-briefing').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(3000);
    const cards = page.locator('#s-briefing .brief-card.show');
    await expect(cards).toHaveCount(3);
    await expect(page.locator('#s-briefing .brief-summary')).toHaveClass(/show/);
  });

  // ── Dispatch section ───────────────────────────────────────────────────────────
  test('dispatch section has 3 agent cards', async ({ page }) => {
    const agents = page.locator('#s-dispatch .disp-agent');
    await expect(agents).toHaveCount(3);
  });

  test('dispatch agents animate progress on scroll', async ({ page }) => {
    await page.locator('#s-dispatch').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(5000);
    // At least one agent should be done
    const doneStatuses = page.locator('#s-dispatch .disp-status.done');
    const count = await doneStatuses.count();
    expect(count).toBeGreaterThanOrEqual(1);
  });

  // ── Compression section ────────────────────────────────────────────────────────
  test('compression section shows before/after panels', async ({ page }) => {
    await expect(page.locator('#s-compression .comp-panel.before')).toBeAttached();
    await expect(page.locator('#s-compression .comp-panel.after')).toBeAttached();
  });

  test('compression counter animates on scroll', async ({ page }) => {
    await page.locator('#s-compression').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(3000);
    const pct = await page.locator('#s-compression .comp-percentage').textContent();
    expect(pct).toBe('89%');
  });

  // ── Methodology section ────────────────────────────────────────────────────────
  test('methodology section has 5 pipeline steps', async ({ page }) => {
    const steps = page.locator('#s-methodology .meth-step');
    await expect(steps).toHaveCount(5);
  });

  test('methodology pipeline lights up on scroll', async ({ page }) => {
    await page.locator('#s-methodology').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(3000);
    const active = page.locator('#s-methodology .meth-step.active');
    await expect(active).toHaveCount(5);
  });

  // ── Debugging section ──────────────────────────────────────────────────────────
  test('debugging section has 4 investigation steps', async ({ page }) => {
    const steps = page.locator('#s-debugging .dbg-step');
    await expect(steps).toHaveCount(4);
  });

  test('debugging steps reveal on scroll', async ({ page }) => {
    await page.locator('#s-debugging').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(4000);
    const shown = page.locator('#s-debugging .dbg-step.show');
    await expect(shown).toHaveCount(4);
  });

  // ── Install & Footer ──────────────────────────────────────────────────────────
  test('install section has steps', async ({ page }) => {
    const steps = page.locator('.install-step');
    const count = await steps.count();
    expect(count).toBeGreaterThan(0);
  });

  test('footer has GitHub and npm links', async ({ page }) => {
    const footer = page.locator('.footer');
    await expect(footer.locator('a', { hasText: 'GitHub' })).toBeVisible();
    await expect(footer.locator('a', { hasText: 'npm' })).toBeVisible();
  });

  // ── TUI embed ──────────────────────────────────────────────────────────────────
  test('TUI inside landing page autoplays demos', async ({ page }) => {
    await page.waitForFunction(() => {
      const input = document.getElementById('input-text');
      return input && input.textContent.length > 0;
    }, { timeout: 5000 });
    const text = await page.locator('#input-text').textContent();
    expect(text.length).toBeGreaterThan(0);
  });

  test('clicking install badge shows "Copied!" feedback', async ({ page }) => {
    await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
    const pathEl = page.locator('#cc-path');
    await pathEl.click();
    await page.waitForTimeout(300);
    await expect(pathEl).toHaveText('Copied!');
    await page.waitForTimeout(1800);
    await expect(pathEl).toHaveText('claude plugin install xgh@extreme-go-horse');
  });

  // ── Screenshots ────────────────────────────────────────────────────────────────
  test('screenshot: hero', async ({ page }) => {
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'out/screenshot-landing-hero.png', fullPage: false });
  });

  test('screenshot: memory section', async ({ page }) => {
    await page.locator('#s-memory').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(4000);
    await page.screenshot({ path: 'out/screenshot-section-memory.png', fullPage: false });
  });

  test('screenshot: briefing section', async ({ page }) => {
    await page.locator('#s-briefing').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'out/screenshot-section-briefing.png', fullPage: false });
  });

  test('screenshot: dispatch section', async ({ page }) => {
    await page.locator('#s-dispatch').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(5000);
    await page.screenshot({ path: 'out/screenshot-section-dispatch.png', fullPage: false });
  });

  test('screenshot: compression section', async ({ page }) => {
    await page.locator('#s-compression').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'out/screenshot-section-compression.png', fullPage: false });
  });

  test('screenshot: methodology section', async ({ page }) => {
    await page.locator('#s-methodology').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(3000);
    await page.screenshot({ path: 'out/screenshot-section-methodology.png', fullPage: false });
  });

  test('screenshot: debugging section', async ({ page }) => {
    await page.locator('#s-debugging').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }));
    await page.waitForTimeout(4000);
    await page.screenshot({ path: 'out/screenshot-section-debugging.png', fullPage: false });
  });

  test('screenshot: full page', async ({ page }) => {
    await page.waitForTimeout(2000);
    await page.screenshot({ path: 'out/screenshot-landing-full.png', fullPage: true });
  });
});
