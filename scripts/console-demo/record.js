// Usage: DEMO_ADMIN_PW=... node record.js [dry|full] [workdir]
// dry: stops before Apply and saves a screenshot per step. full: applies the changes (they change the demo controller).
const {chromium} = require('playwright');
const fs = require('fs');
const MODE = process.argv[2] || 'dry';
const URL = process.env.DEMO_URL || 'http://127.0.0.1:8099';
const OUT = require('path').resolve(process.argv[3] || '.', 'out-' + MODE);
fs.rmSync(OUT, {recursive: true, force: true}); fs.mkdirSync(OUT);

const CURSOR = `
(() => {
  const add = () => {
    if (document.getElementById('demo-cursor')) return;
    const c = document.createElement('div'); c.id = 'demo-cursor';
    c.innerHTML = '<svg width="22" height="28" viewBox="0 0 22 28"><path d="M1 1 L1 22 L6.5 17 L10.5 26 L14 24.5 L10 15.8 L17 15.8 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/></svg>';
    Object.assign(c.style, {position:'fixed', left:'0', top:'0', zIndex: 2147483647, pointerEvents:'none', transform:'translate(-200px,-200px)', transition:'none'});
    document.documentElement.appendChild(c);
    const ring = document.createElement('div'); ring.id = 'demo-ring';
    Object.assign(ring.style, {position:'fixed', width:'34px', height:'34px', marginLeft:'-17px', marginTop:'-17px', borderRadius:'50%', border:'3px solid rgba(30,90,255,.75)', zIndex: 2147483646, pointerEvents:'none', opacity:'0', transition:'opacity .35s, transform .35s', transform:'scale(.4)'});
    document.documentElement.appendChild(ring);
    addEventListener('mousemove', e => { c.style.transform = 'translate(' + (e.clientX - 1) + 'px,' + (e.clientY - 1) + 'px)'; }, true);
    addEventListener('mousedown', e => { ring.style.left = e.clientX + 'px'; ring.style.top = e.clientY + 'px'; ring.style.transition = 'none'; ring.style.opacity = '1'; ring.style.transform = 'scale(.4)';
      requestAnimationFrame(() => { ring.style.transition = 'opacity .5s, transform .5s'; ring.style.transform = 'scale(1.1)'; ring.style.opacity = '0'; }); }, true);
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', add); else add();
})();`;

(async () => {
  const b = await chromium.launch();
  // Log in outside the recording.
  const lc = await b.newContext({viewport: {width: 1440, height: 900}});
  const lp = await lc.newPage();
  await lp.goto(URL + '/');
  await lp.fill('#Username', 'admin');
  await lp.fill('#Password', process.env.DEMO_ADMIN_PW);
  await lp.click('text=LOG IN');
  await lp.waitForTimeout(3000);
  const state = await lc.storageState();
  await lc.close();

  const ctx = await b.newContext({viewport: {width: 1440, height: 900}, storageState: state,
    recordVideo: {dir: OUT, size: {width: 1440, height: 900}}});
  await ctx.addInitScript(CURSOR);
  const p = await ctx.newPage();
  p.setDefaultTimeout(8000);
  const t0 = Date.now();
  const caps = [];
  let shot = 0;
  const T = () => (Date.now() - t0) / 1000;
  const cap = async (text, hold = 2600) => { console.log("cap", T().toFixed(1), text.slice(0, 40)); caps.push({t: T(), text}); await p.waitForTimeout(hold); };
  const snap = async (n) => { if (MODE === 'dry') await p.screenshot({path: `${OUT}/${String(++shot).padStart(2, '0')}-${n}.png`}); };
  const wait = ms => p.waitForTimeout(ms);
  let cur = {x: 720, y: 450};
  const moveTo = async (x, y, steps = 25) => { await p.mouse.move(x, y, {steps}); cur = {x, y}; };
  const center = async loc => { const bb = await loc.boundingBox(); if (!bb) throw new Error('no box'); return {x: bb.x + bb.width / 2, y: bb.y + bb.height / 2}; };
  const go = async loc => { const c = await center(loc); await moveTo(c.x, c.y); return c; };
  const click = async loc => { console.log("click", String(loc).slice(0, 90)); await go(loc); await wait(250); await p.mouse.down(); await wait(80); await p.mouse.up(); };
  const typeSlow = async (s) => p.keyboard.type(s, {delay: 90});
  const drag = async (from, to, opts = {}) => {
    const a = await go(from); await wait(300);
    if (opts.alt) await p.keyboard.down('Alt');
    await p.mouse.down(); await wait(150);
    const c = await center(to);
    await moveTo(a.x + 12, a.y + 8, 5);
    await moveTo(c.x, c.y, 40); await wait(400);
    await p.mouse.up();
    if (opts.alt) await p.keyboard.up('Alt');
  };
  const member = (group, name) => p.locator('.ab-node.ab-group', {has: p.locator('.ab-attr', {hasText: new RegExp('^#?' + group + '$')})}).locator('.ab-row', {hasText: name}).first();
  const groupHead = (group) => p.locator('.ab-node.ab-group', {has: p.locator('.ab-attr', {hasText: new RegExp('^#?' + group + '$')})}).locator('.ab-gh').first();
  const free = name => p.locator('.ab-node.ab-free', {hasText: name}).first();
  const btn = (text) => p.locator('button', {hasText: text}).first();

  await p.goto(URL + '/access-canvas');
  await p.waitForSelector('.ab-node', {timeout: 30000});
  await wait(1500);
  const tStart = T();
  await moveTo(900, 520, 10);

  // 1. Overview
  await cap('The Access Canvas draws an OpenZiti network as one picture: who can use which service, and through which policies.', 4200);
  await go(p.locator('.ac-legend')); await wait(300);
  await cap('Left: identity groups (by role attribute). Middle: service groups. Right: the identities that host them. Lines are policies.', 4600);
  await snap('overview');

  // 2. Zoom and pan
  const vp = await center(p.locator('.ab-viewport'));
  await moveTo(vp.x - 180, vp.y - 60);
  await cap('Zoom with the mouse wheel or a pinch, + / - keys, or the zoom buttons. Drag the background to pan.', 800);
  for (let i = 0; i < 4; i++) { await p.mouse.wheel(0, -240); await wait(260); }
  await wait(900);
  await moveTo(vp.x, vp.y + 150, 15);
  await p.mouse.down(); await moveTo(vp.x + 160, vp.y + 220, 30); await p.mouse.up();
  await wait(1200);
  await snap('zoomed');
  await click(btn('Fit')); await wait(1400);

  // 3. Name filter
  const search = p.locator('.ac-page input[placeholder^="Filter by name"]');
  await click(search);
  await cap('Filter by any part of a name. A group stays visible but shows only the members that match.', 600);
  await typeSlow('erin'); await wait(2400);
  await snap('filter-name');
  await p.keyboard.press(process.platform === 'darwin' ? 'Meta+A' : 'Control+A'); await p.keyboard.press('Backspace');
  await wait(800);

  // 4. Filters menu
  await click(btn('Filters'));
  await cap('Filters show or hide identities, services and routers, or only the groups for chosen attributes.', 1600);
  await snap('filters-menu');
  const routerChip = p.locator('.ac-popmenu .ac-chipbtn[data-kind="router"]');
  if (await routerChip.count()) { await click(routerChip); await wait(1200); await snap('filters-norouters'); }
  await cap('Hiding routers here leaves more room for identities and services.', 1800);
  await p.keyboard.press('Escape'); await wait(300); if (await p.locator('.ac-menu-catch').count()) await click(p.locator('.ac-menu-catch').first());
  await wait(500);
  await click(btn('Fit')); await wait(1400);

  // 5. Problems
  await click(p.locator('.ac-probbtn'));
  await cap('“Items need attention” opens a table of problems: each item counted once, with the reason and a hint. It can be filtered and sorted.', 4200);
  await snap('problems');
  const row = p.locator('.ac-ptable tbody tr', {hasText: 'dbas-dial-databases'}).first();
  const target = (await row.count()) ? row : p.locator('.ac-ptable tbody tr').first();
  await go(target); await wait(700);
  await cap('dbas-dial-databases selects nobody: no identity has #dbas yet. “Show” finds it on the canvas.', 1200);
  await click(target.locator('button', {hasText: 'Show'})); await wait(2600);
  await snap('problem-shown');
  await click(btn('Fit')); await wait(1200);

  // 6. Fix it by dragging
  await cap('Fix it by dragging: drop dave-laptop on the empty #dbas group, which gives it the #dbas attribute.', 600);
  await drag(free('dave-laptop'), groupHead('dbas'));
  await wait(2200);
  await snap('dragged');
  await cap('Nothing is sent yet. The change is queued, and dashed lines show the pending result.', 3000);

  // 7. Copy / paste
  await cap('Copy and paste access: select alice-laptop and press ⌘C (Ctrl+C)…', 400);
  await click(member('engineering', 'alice-laptop')); await wait(500);
  await p.keyboard.press('ControlOrMeta+c'); await wait(1600);
  await cap('…then select the #finance group and press ⌘V. Alice joins #finance too. ⌘X cuts, to move instead.', 400);
  await click(groupHead('finance')); await wait(500);
  await p.keyboard.press('ControlOrMeta+v'); await wait(2400);
  await snap('pasted');

  // 8. Check access
  await cap('Double-click an identity to check its access, pending changes included. dave-laptop is now allowed to Dial, but isn’t enrolled yet.', 400);
  { const c = await go(member('dbas', 'dave-laptop')); await wait(300); await p.mouse.dblclick(c.x, c.y); }
  await wait(4200);
  await snap('advisor');

  // 9. Pending changes
  await click(p.locator('.ac-dockbtn', {hasText: 'pending'}));
  await cap('Pending changes lists each edit with the exact API calls. Discard any of them, or apply them all at once.', 4200);
  await snap('pending');
  if (MODE === 'full') {
    await click(p.locator('.ac-drawer .ac-btn.primary', {hasText: 'Apply'}));
    await wait(4000);
    await cap('Applied. The canvas reloads from the controller, and the #dbas problem is gone. Undo last apply reverts it.', 3800);
  }
  await p.keyboard.press('Escape');
  await click(p.locator('.ac-drawer .ac-icon-btn[aria-label="Close"]')).catch(() => {});
  await wait(800);

  // 10. Wizard
  await click(btn('Set up a service'));
  await cap('The “Set up a service” wizard creates everything one service needs, using common names and choices.', 3000);
  await click(p.locator('.ac-wiz-tpl', {hasText: 'SSH'}));
  await click(p.locator('.ac-wiz input').first());
  await typeSlow('build-01'); await wait(500);
  await cap('Step 1: pick the kind of service and name the server. It suggests build-01-ssh, reached at build-01.ziti:22.', 2600);
  await snap('wiz-1');
  await click(btn('Next')); await wait(600);
  await cap('Step 2: the identity that hosts it: a new identity for the server, with a #build-01-ssh-hosts attribute for the Bind policy.', 3600);
  await snap('wiz-2');
  await click(btn('Next')); await wait(600);
  await click(p.locator('.ac-wiz-groups .ac-chipbtn', {hasText: 'Developers'}));
  await cap('Step 3: who may use it. Groups usually suited to SSH are marked “suggested”. Here: Developers…', 1600);
  const dev = p.locator('.ac-wiz input[placeholder="e.g. jdoe-laptop"]');
  await click(dev); await typeSlow('jdoe-laptop'); await wait(400);
  await cap('…plus a new device identity for the user, jdoe-laptop. One identity per device.', 2200);
  await snap('wiz-3');
  await click(btn('Next')); await wait(600);
  await cap('Step 4: review. Two new identities (server and user device), two configs, the service, Bind and Dial policies.', 4600);
  await snap('wiz-4');
  await click(btn('Add to pending changes')); await wait(1800);
  await snap('wiz-queued');
  await cap('The new pieces appear on the canvas as pending, ready to review and apply like any other change.', 3600);
  if (MODE === 'full') {
    await click(p.locator('.ac-dockapply')); await wait(4500);
    await click(p.locator('.ac-dockbtn', {hasText: /pending|changes/})).catch(() => {});
    await wait(800);
    await cap('After applying, “To finish” lists what is left to do by hand, such as enrolling build-01 and jdoe-laptop.', 4200);
    await snap('done');
  }
  await cap('Access Canvas and the Set up a service wizard, in the Ziti Admin Console.', 3000);
  const tEnd = T();
  fs.writeFileSync(OUT + '/captions.json', JSON.stringify({tStart, tEnd, caps}, null, 1));
  await ctx.close(); await b.close();
  console.log('done', tStart, tEnd, caps.length);
})().catch(e => { console.error(e); process.exit(1); });
