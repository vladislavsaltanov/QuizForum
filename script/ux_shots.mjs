import { chromium } from "/Users/kowie/.local/share/fnm/node-versions/v24.21.0/installation/lib/node_modules/playwright/index.mjs";

const base = "http://127.0.0.1:3001";
const out = "/tmp/ux-shots";
import fs from "fs";
fs.mkdirSync(out, { recursive: true });

const browser = await chromium.launch();
const shots = [];

async function login(page, email) {
  await page.goto(base + "/session/new");
  await page.fill('input#email', email);
  await page.fill('input[type="password"]', "ux-pass-1234");
  await page.click('button[type="submit"]');
  await page.waitForLoadState("networkidle");
}

async function snap(page, name, url, viewport = { width: 1280, height: 900 }) {
  await page.setViewportSize(viewport);
  await page.goto(base + url, { waitUntil: "networkidle" });
  await page.screenshot({ path: `${out}/${name}.png`, fullPage: true });
  shots.push(name);
}

const page = await browser.newPage();
// Wizard pass as the RESPONDER (owner gets the read-only author view, no wizard).
await login(page, "uxtwo@example.com");

await snap(page, "01-dash", "/tests");
await snap(page, "02-home-strip", "/");
await snap(page, "03-open-wizard", "/tests/3");
await page.waitForTimeout(600);
await snap(page, "04-gate", "/tests/4");
await snap(page, "05-draft-edit", "/tests/5");
await snap(page, "06-closed-results", "/tests/6");

await page.click('form[data-wizard] .qf-wizard-next').catch(() => {});
await page.waitForTimeout(400);
await snap(page, "07-wizard-step2", "/tests/3");

// Mobile pass
await snap(page, "08-dash-mobile", "/tests", { width: 390, height: 844 });
await snap(page, "09-wizard-mobile", "/tests/3", { width: 390, height: 844 });
await snap(page, "10-home-mobile", "/", { width: 390, height: 844 });

await browser.close();
console.log(shots.join(" "));
