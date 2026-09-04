#!/usr/bin/env node

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync } = require('node:child_process');
const { chromium } = require('playwright');

const [siteArgument, baseURLArgument, reportArgument] = process.argv.slice(2);
if (!siteArgument || !baseURLArgument || !reportArgument || process.argv.length !== 5) {
  console.error('Usage: watch-support-site-render-check.cjs <support-site-repository> <local-base-url> <new-report-directory>');
  process.exit(64);
}

function fail(message) {
  throw new Error(`WellSpent support-site render check failed: ${message}`);
}

const siteRoot = fs.realpathSync(siteArgument);
if (!fs.statSync(path.join(siteRoot, '.git')).isDirectory()) fail('support-site Git repository is missing');
const reportParent = fs.realpathSync(path.dirname(reportArgument));
const reportDirectory = path.join(reportParent, path.basename(reportArgument));
if (fs.existsSync(reportDirectory)) fail('report directory already exists; preserve earlier evidence');
if (`${reportDirectory}${path.sep}`.startsWith(`${siteRoot}${path.sep}`)) fail('report must be outside the support-site repository');

const baseURL = new URL(baseURLArgument);
if (!['127.0.0.1', 'localhost'].includes(baseURL.hostname)) fail('render source must be localhost');
if (baseURL.protocol !== 'http:') fail('render source must use local HTTP');

const sourceCommit = execFileSync('git', ['-C', siteRoot, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const sourceTree = execFileSync('git', ['-C', siteRoot, 'rev-parse', 'HEAD^{tree}'], { encoding: 'utf8' }).trim();
const status = execFileSync('git', ['-C', siteRoot, 'status', '--porcelain=v1'], { encoding: 'utf8' });
if (status !== '') fail('support-site checkout is dirty');
if (!/^[0-9a-f]{40}$/.test(sourceCommit) || !/^[0-9a-f]{40}$/.test(sourceTree)) fail('invalid support-site source identity');

const stylesheet = fs.readFileSync(path.join(siteRoot, 'styles.css'));
const favicon = fs.readFileSync(path.join(siteRoot, 'favicon.svg'));
const scratchDirectory = fs.mkdtempSync(path.join(os.tmpdir(), 'WellSpentSupportRender.'));
const scenarios = [
  { name: 'root-desktop', route: '/', width: 1440, height: 900 },
  { name: 'root-mobile', route: '/', width: 390, height: 844 },
  { name: 'support-desktop', route: '/support/', width: 1440, height: 900 },
  { name: 'support-mobile', route: '/support/', width: 390, height: 844 },
  { name: 'support-mobile-expanded', route: '/support/', width: 390, height: 844, expandFAQ: true },
  { name: 'privacy-desktop', route: '/privacy/', width: 1440, height: 900 },
  { name: 'privacy-mobile', route: '/privacy/', width: 390, height: 844 }
];

async function inspectLayout(page) {
  return page.evaluate(() => {
    const documentElement = document.documentElement;
    const viewportWidth = documentElement.clientWidth;
    const overflowElements = [...document.body.querySelectorAll('*')]
      .map((element) => {
        const rect = element.getBoundingClientRect();
        return {
          tag: element.tagName.toLowerCase(),
          className: typeof element.className === 'string' ? element.className : '',
          left: Number(rect.left.toFixed(2)),
          right: Number(rect.right.toFixed(2)),
          width: Number(rect.width.toFixed(2))
        };
      })
      .filter((item) => item.width > 0 && (item.left < -0.5 || item.right > viewportWidth + 0.5))
      .slice(0, 20);

    return {
      title: document.title,
      heading: document.querySelector('h1')?.textContent?.trim() ?? '',
      viewportWidth,
      scrollWidth: documentElement.scrollWidth,
      scrollHeight: documentElement.scrollHeight,
      horizontalOverflow: documentElement.scrollWidth > viewportWidth + 1 || overflowElements.length > 0,
      overflowElements
    };
  });
}

(async () => {
  let browser;
  const results = [];
  try {
    browser = await chromium.launch({
      headless: true,
      executablePath: '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      args: ['--disable-gpu']
    });

    for (const scenario of scenarios) {
      const context = await browser.newContext({
        viewport: { width: scenario.width, height: scenario.height },
        deviceScaleFactor: 1,
        colorScheme: 'light',
        reducedMotion: 'reduce'
      });
      const page = await context.newPage();
      const consoleErrors = [];
      const pageErrors = [];
      page.on('console', (message) => {
        if (message.type() === 'error') consoleErrors.push(message.text());
      });
      page.on('pageerror', (error) => pageErrors.push(error.message));
      await page.route('https://wellspent-holdings.github.io/styles.css', (route) => route.fulfill({
        status: 200,
        contentType: 'text/css; charset=utf-8',
        body: stylesheet
      }));
      await page.route('https://wellspent-holdings.github.io/favicon.svg', (route) => route.fulfill({
        status: 200,
        contentType: 'image/svg+xml',
        body: favicon
      }));

      const response = await page.goto(new URL(scenario.route, baseURL).href, { waitUntil: 'networkidle' });
      if (!response || !response.ok()) fail(`${scenario.name} HTTP response`);
      if (scenario.expandFAQ) {
        await page.locator('details').evaluateAll((details) => details.forEach((detail) => { detail.open = true; }));
      }
      await page.evaluate(() => document.fonts.ready);
      const layout = await inspectLayout(page);
      const screenshot = `${scenario.name}.png`;
      await page.screenshot({ path: path.join(scratchDirectory, screenshot), fullPage: true, animations: 'disabled' });
      results.push({
        scenario: scenario.name,
        route: scenario.route,
        viewport: { width: scenario.width, height: scenario.height, deviceScaleFactor: 1 },
        screenshot,
        httpStatus: response.status(),
        consoleErrors,
        pageErrors,
        ...layout
      });
      await context.close();
    }
  } finally {
    if (browser) await browser.close();
  }

  const passed = results.every((result) =>
    result.httpStatus === 200 &&
    result.consoleErrors.length === 0 &&
    result.pageErrors.length === 0 &&
    result.horizontalOverflow === false
  );
  fs.mkdirSync(reportDirectory);
  for (const result of results) {
    fs.copyFileSync(path.join(scratchDirectory, result.screenshot), path.join(reportDirectory, result.screenshot));
  }
  const summary = {
    schemaVersion: 1,
    observedAt: new Date().toISOString(),
    rawIdentifiersRetained: false,
    publicationPerformed: false,
    inspection: passed ? 'passed' : 'failed',
    source: { commit: sourceCommit, tree: sourceTree },
    scenarios: results
  };
  fs.writeFileSync(path.join(reportDirectory, 'summary.json'), `${JSON.stringify(summary, null, 2)}\n`);
  fs.rmSync(scratchDirectory, { recursive: true });

  if (!passed) {
    console.error(`WellSpent support-site render check failed. Diagnostic evidence: ${path.join(reportDirectory, 'summary.json')}`);
    process.exit(1);
  }
  console.log(`WellSpent support-site render check passed. Nothing was published. Evidence: ${path.join(reportDirectory, 'summary.json')}`);
})().catch((error) => {
  try { fs.rmSync(scratchDirectory, { recursive: true, force: true }); } catch {}
  console.error(error.message);
  process.exit(1);
});
