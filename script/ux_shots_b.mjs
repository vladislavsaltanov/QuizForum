import { chromium } from "/Users/kowie/.local/share/fnm/node-versions/v24.21.0/installation/lib/node_modules/playwright/index.mjs";
import fs from "fs";
const base = "http://127.0.0.1:3001";
const out = "/tmp/ux-shots";
fs.mkdirSync(out, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage();
page.on("console", (m) => { if (m.type() === "error") console.log("JSERR:", m.text()); });

async function login(email) {
  await page.setViewportSize({ width: 1280, height: 900 });
  await page.goto(base + "/session/new");
  await page.fill('input#email', email);
  await page.fill('input[type="password"]', "ux-pass-1234");
  await page.click('button[type="submit"]');
  await page.waitForLoadState("networkidle");
}

async function snap(name, url, vp = { width: 1280, height: 900 }) {
  await page.setViewportSize(vp);
  await page.goto(base + url, { waitUntil: "networkidle" });
  await page.waitForTimeout(700);
  await page.screenshot({ path: `${out}/${name}.png`, fullPage: true });
}

await login("uxthree@example.com");
await snap("11-wizard-fresh", "/tests/3");
await snap("12-gate-fresh", "/tests/4");
await snap("13-wizard-mobile-fresh", "/tests/3", { width: 390, height: 844 });

// Wizard interaction: type into step 1, go next.
await page.goto(base + "/tests/3", { waitUntil: "networkidle" });
await page.fill('form[data-wizard] .qf-step[data-step="0"] textarea', "восемь ног");
const next = page.locator('form[data-wizard] .qf-step[data-step="0"] .qf-wizard-next');
await next.click();
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/14-wizard-step2-real.png`, fullPage: true });

// Type nothing in step 1 then click Далее: inline hint must appear.
await page.goto(base + "/tests/3", { waitUntil: "networkidle" });
const nextBtn = page.locator('form[data-wizard] .qf-step[data-step="0"] .qf-wizard-next');
await nextBtn.click();
await page.waitForTimeout(400);
await page.screenshot({ path: `${out}/15-wizard-hint.png`, fullPage: true });

// Answer everything, submit, expect confirmed attempt.
await page.fill('form[data-wizard] .qf-step[data-step="0"] textarea', "восемь");
await nextBtn.click();
await page.locator('form[data-wizard] .qf-step[data-step="1"] input[type="radio"]').first().click();
await page.click('form[data-wizard] button[type="submit"]');
await page.waitForLoadState("networkidle");
await page.screenshot({ path: `${out}/16-after-submit.png`, fullPage: true });

await page.setViewportSize({ width: 390, height: 844 });
await page.goto(base + "/", { waitUntil: "networkidle" });
await page.screenshot({ path: `${out}/17-home-mobile.png`, fullPage: true });

await browser.close();
console.log("done");
