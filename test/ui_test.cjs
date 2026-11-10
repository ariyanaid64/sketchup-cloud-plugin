const { chromium } = require('playwright');
const { execFileSync } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
const fs = require('node:fs');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
function calculate(payload) {
  return JSON.parse(execFileSync('ruby', [path.join(__dirname, 'preview_payload.rb')], {
    input: JSON.stringify(payload), encoding: 'utf8'
  }));
}

(async () => {
  const browser = await chromium.launch({
    executablePath: process.env.CHROME_PATH || '/usr/local/bin/google-chrome',
    headless: true, args: ['--no-sandbox']
  });
  const page = await browser.newPage({ viewport: { width: 480, height: 900 }, deviceScaleFactor: 1 });
  const errors = [];
  const previews = [];
  const creates = [];
  let kind = 'drawer', cancels = 0;
  const space = {width: 900, depth: 550, height: 720};
  page.on('pageerror', error => errors.push(error.message));
  await page.exposeFunction('hostReady', async () => {
    await page.evaluate(data => DMP.load(data), {kind, mode: 'create', space, params: calculate({kind, normalize: true})});
  });
  await page.exposeFunction('hostPreview', async json => {
    const input = {...JSON.parse(json), kind};
    const result = calculate(input);
    await page.evaluate(result => result.error ? DMP.error(result.error, result.requestId) : DMP.preview(result), result);
    previews.push({input, result});
  });
  await page.exposeFunction('hostCreate', async json => {
    const input = {...JSON.parse(json), kind};
    const result = calculate(input);
    creates.push({input, result});
    await page.evaluate(result => { DMP.busy(false); if (result.error) DMP.error(result.error); }, result);
  });
  await page.exposeFunction('hostCancel', () => { cancels++; });
  await page.addInitScript(() => {
    window.sketchup = {ready: () => hostReady(), preview: json => hostPreview(json), create: json => hostCreate(json), cancel: () => hostCancel()};
  });
  async function updated(action, expectError = false) {
    const before = previews.length;
    await action();
    const until = Date.now() + 5000;
    while (previews.length === before && Date.now() < until) await page.waitForTimeout(40);
    assert.ok(previews.length > before, 'Ruby preview bridge responded');
    const result = previews.at(-1).result;
    assert.equal(Boolean(result.error), expectError, result.error || 'Expected invalid preview');
    if (!expectError) assert.ok(await page.locator('#preview polygon').count() > 0, 'real geometry rendered');
    return result;
  }
  await updated(() => page.goto(pathToFileURL(path.join(root, 'src/drawer_maker_pro/html/dialog.html')).href));
  assert.equal(await page.locator('#space_width').getAttribute('readonly'), '');
  for (const preset of ['metal', 'rail', 'shaker', 'glass', 'wooden']) {
    await updated(() => page.locator(`[data-preset="${preset}"]`).click());
  }
  await updated(() => page.locator('[data-preset="shaker"]').click());
  await updated(() => page.locator('[data-field="quantity"]').fill('1:1:2'));
  assert.equal(previews.at(-1).input.params.quantity, '1:1:2');
  await updated(() => page.locator('[data-field="quantity"]').fill('0'), true);
  assert.equal(await page.locator('#error').isVisible(), true);
  await updated(() => page.locator('[data-field="quantity"]').fill('3'));
  await page.locator('[data-view="iso"]').click();
  assert.ok(await page.locator('#preview polygon').count() > previews.at(-1).result.parts.length);
  // Keyboard activation of a view button must not submit the form.
  await page.locator('[data-view="front"]').focus();
  await page.keyboard.press('Enter');
  assert.equal(creates.length, 0);
  await page.locator('[data-view="iso"]').click();
  await page.locator('#create').click();
  await page.waitForFunction(() => !document.querySelector('#create').disabled);
  assert.equal(creates.length, 1);
  assert.equal(creates[0].input.params.front_style, 'shaker');
  assert.equal(creates[0].result.error, undefined);
  const evidence = process.env.DMP_EVIDENCE || '/tmp/verify';
  fs.mkdirSync(evidence, {recursive: true});
  await page.locator('.content').evaluate(el => el.scrollTop = 0);
  await page.screenshot({path: path.join(evidence, 'drawer-workshop.png')});

  kind = 'cabinet';
  await updated(() => page.evaluate(data => DMP.load(data), {kind, mode: 'create', space: {width: 900, depth: 560, height: 800}, params: calculate({kind, normalize: true})}));
  for (const preset of ['base', 'wall', 'glass', 'tall']) {
    await updated(() => page.locator(`[data-preset="${preset}"]`).click());
  }
  await updated(() => page.locator('[data-preset="glass"]').click());
  await updated(() => page.locator('#space_width').fill('1200'));
  assert.equal(previews.at(-1).input.space.width, 1200);
  await updated(() => page.locator('[data-field="columns"]').fill('1:2'));
  assert.equal(previews.at(-1).input.params.columns, '1:2');
  await page.locator('#create').click();
  await page.waitForFunction(() => !document.querySelector('#create').disabled);
  assert.equal(creates.length, 2);
  assert.equal(creates[1].result.error, undefined);
  await page.locator('[data-view="iso"]').click();
  await page.locator('.content').evaluate(el => el.scrollTop = 0);
  await page.screenshot({path: path.join(evidence, 'cabinet-workshop.png')});

  await updated(() => page.evaluate(data => DMP.load(data), {kind, mode: 'edit', space: {width: 900, depth: 560, height: 800}, params: calculate({kind, normalize: true})}));
  assert.equal(await page.locator('#space_width').getAttribute('readonly'), '');
  assert.equal(await page.locator('#create').textContent(), 'Terapkan perubahan');
  // A stale response must not replace the newest valid geometry.
  const svg = await page.locator('#preview').innerHTML();
  await page.evaluate(() => { DMP.preview({requestId: -1, parts: []}); DMP.error('stale', -1); });
  assert.equal(await page.locator('#preview').innerHTML(), svg);
  assert.equal(await page.locator('#error').isVisible(), false);
  await page.setViewportSize({width: 360, height: 640});
  assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true);
  await page.locator('#cancel').click();
  await page.waitForTimeout(100);
  assert.equal(cancels, 1);
  assert.deepEqual(errors, []);
  await browser.close();
  console.log(`UI passed: ${previews.length} Ruby-backed previews, drawer/cabinet presets, validation, create/edit payloads, keyboard, responsive layout, screenshots.`);
})().catch(error => { console.error(error); process.exit(1); });
