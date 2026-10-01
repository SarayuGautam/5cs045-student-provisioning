// End-to-end test of the admin panel in a real browser (Playwright).
// Run it from any computer that is on the panel's allowed list and has Node.js:
//
//   npm install playwright && npx playwright install chromium
//   ADMIN_URL=https://10.80.0.250:8443 ADMIN_USER=fullstack ADMIN_PASSWORD='...' node test/admin-panel-e2e.js
//
// It signs in, creates a throwaway student called e2e_check, changes its password and disk
// limit, removes it again, and checks that bad input and bad passwords are refused.
// Add SCREENSHOTS=folder to save a picture of every page.
'use strict';

const { chromium } = require('playwright');
const assert = require('assert/strict');

const BASE = (process.env.ADMIN_URL || 'https://127.0.0.1:8443').replace(/\/$/, '');
const USER = process.env.ADMIN_USER || 'fullstack';
const PASSWORD = process.env.ADMIN_PASSWORD;
const SHOTS = process.env.SCREENSHOTS || '';
const STUDENT = 'e2e_check';

if (!PASSWORD) {
  console.error('Set ADMIN_PASSWORD (and ADMIN_URL, ADMIN_USER if not the defaults).');
  process.exit(2);
}

let passed = 0;
let failed = 0;
async function check(name, fn) {
  try {
    await fn();
    passed++;
    console.log(`  PASS: ${name}`);
  } catch (e) {
    failed++;
    console.log(`  FAIL: ${name}\n        ${String(e.message).split('\n')[0]}`);
  }
}

(async () => {
  const browser = await chromium.launch();
  const context = await browser.newContext({ ignoreHTTPSErrors: true, viewport: { width: 1280, height: 860 } });
  const page = await context.newPage();
  const problems = [];
  page.on('pageerror', (e) => problems.push(e.message));
  page.on('response', (r) => { if (r.status() >= 500) problems.push(`${r.status()} from ${r.url()}`); });
  const shot = async (name) => { if (SHOTS) await page.screenshot({ path: `${SHOTS}/${name}.png`, fullPage: true }); };
  const flash = () => page.locator('.flash').first().innerText();

  console.log(`=== admin panel at ${BASE} ===`);

  await check('signed-out visitors are sent to the sign-in page', async () => {
    await page.goto(`${BASE}/students`);
    assert.match(page.url(), /\/login$/);
  });

  await check('a wrong password is refused', async () => {
    await page.fill('input[name=username]', USER);
    await page.fill('input[name=password]', 'definitely-not-the-password');
    await page.click('button[type=submit]');
    assert.match(await flash(), /Wrong username or password/);
  });

  await check('the fullstack superadmin can sign in', async () => {
    await page.fill('input[name=password]', PASSWORD);
    await page.click('button[type=submit]');
    await page.waitForURL(`${BASE}/`);
    await page.getByRole('heading', { name: 'Who needs help?' }).waitFor();
    await shot('students');
  });

  // Leftover from an earlier run that stopped halfway
  const removeOpen = 'details.fix-danger > summary';
  await page.goto(`${BASE}/students/${STUDENT}`);
  if (await page.locator('form[action$="/remove"]').count()) {
    await page.click(removeOpen);
    await page.fill('input[name=confirm]', STUDENT);
    await page.click('form[action$="/remove"] button[type=submit]');
    await page.waitForURL(`${BASE}/`);
  }

  let firstPassword = '';
  await check('a student can be added from the Students page', async () => {
    await page.goto(`${BASE}/`);
    await page.click('#add-form summary');
    await page.fill('#add-form input[name=username]', STUDENT);
    await page.fill('#add-form input[name=full_name]', 'E2E Check');
    await page.click('#add-form button[type=submit]');
    await page.waitForURL(`${BASE}/students/${STUDENT}`);
    firstPassword = (await page.locator('#secret-pw').innerText()).trim();
    assert.equal(firstPassword.length, 14);
    assert.equal(await page.locator('.spell li').count(), 14);
    await shot('student-new');
  });

  await check('the new password is shown only once', async () => {
    await page.reload();
    assert.equal(await page.locator('#secret-pw').count(), 0);
  });

  await check('adding the same username again is refused', async () => {
    await page.goto(`${BASE}/`);
    await page.click('#add-form summary');
    await page.fill('#add-form input[name=username]', STUDENT);
    await page.click('#add-form button[type=submit]');
    await page.waitForURL(`${BASE}/`);
    assert.match(await page.locator('.panel .flash-error').innerText(), /already exists/);
  });

  await check('typing a name finds the student, and Enter opens them beside the list', async () => {
    await page.goto(`${BASE}/`);
    await page.fill('[data-finder]', 'e2e che');
    assert.equal(await page.locator('.person:visible').count(), 1);
    await page.keyboard.press('Enter');
    await page.waitForURL(`${BASE}/students/${STUDENT}`);
    await page.locator('.panel h2', { hasText: 'E2E Check' }).waitFor();
    assert.equal(await page.locator('.person.is-selected').count(), 1);
  });

  await check('the disk limit can be changed', async () => {
    await page.click('details.fix:has(form[action$="/quota"]) > summary');
    await page.fill('input[name=mb]', '1024');
    await page.click('form[action$="/quota"] button[type=submit]');
    assert.match(await flash(), /1\.0 GB|not enforced/);
  });

  await check('an impossible disk limit is refused', async () => {
    await page.click('details.fix:has(form[action$="/quota"]) > summary');
    await page.fill('input[name=mb]', '999999');
    await page.$eval('form[action$="/quota"]', (f) => f.noValidate = true);
    await page.click('form[action$="/quota"] button[type=submit]');
    assert.match(await flash(), /between 50 MB and 20 GB/);
  });

  await check('the password can be reset', async () => {
    await page.click('details.fix:has(form[action$="/reset"]) > summary');
    const box = page.locator('form[action$="/reset"] input[name=send_email]');
    if (await box.isChecked()) await box.uncheck();
    await page.click('form[action$="/reset"] button[type=submit]');
    const second = (await page.locator('#secret-pw').innerText()).trim();
    assert.equal(second.length, 14);
    assert.notEqual(second, firstPassword);
  });

  await check('forms without the hidden security token are refused', async () => {
    await page.evaluate((u) => fetch(`/students/${u}/password`,
      { method: 'POST', body: new URLSearchParams({ csrf: 'wrong' }), redirect: 'manual' }), STUDENT);
    await page.goto(`${BASE}/students/${STUDENT}`);
    assert.equal(await page.locator('#secret-pw').count(), 0);
    assert.match(await flash(), /form had expired/);
  });

  await check('removing needs the username typed exactly', async () => {
    await page.click(removeOpen);
    const button = page.locator('form[action$="/remove"] button[type=submit]');
    assert.equal(await button.isDisabled(), true);
    await page.fill('form[action$="/remove"] input[name=confirm]', 'e2e_chec');
    assert.equal(await button.isDisabled(), true);
    await page.fill('form[action$="/remove"] input[name=confirm]', STUDENT);
    assert.equal(await button.isDisabled(), false);
    await button.click();
    await page.waitForURL(`${BASE}/`);
    assert.match(await flash(), /was removed/);
    assert.equal(await page.locator(`a.person[href="/students/${STUDENT}"]`).count(), 0);
  });

  await check('a bad address is refused on the Security page', async () => {
    await page.goto(`${BASE}/security`);
    const current = await page.locator('textarea[name=entries]').inputValue();
    await page.fill('textarea[name=entries]', `${current}\nnot-an-address`);
    await page.click('form[action="/security/allowlist"] button[type=submit]');
    assert.match(await flash(), /not an IP address/);
    assert.equal(await page.locator('textarea[name=entries]').inputValue(), current);
    await shot('security');
  });

  await check('the Server page shows every service', async () => {
    await page.goto(`${BASE}/server`);
    assert.equal(await page.locator('.services li').count(), 7);
  });

  await check('every change is in the admin log', async () => {
    await page.goto(`${BASE}/logs?log=admin&q=${STUDENT}`);
    const text = await page.locator('.log-list').innerText();
    for (const want of [`added student ${STUDENT}`, `reset the password of ${STUDENT}`, `removed student ${STUDENT}`]) {
      assert.ok(text.includes(want), `missing: ${want}`);
    }
  });

  await check('signing out ends the session', async () => {
    await page.click('.signout button');
    await page.waitForURL(`${BASE}/login`);
    await page.goto(`${BASE}/`);
    assert.match(page.url(), /\/login$/);
  });

  await check('no script errors on any page', async () => {
    assert.deepEqual(problems, [], problems.join(' / '));
  });

  await browser.close();
  console.log(`\n ${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
