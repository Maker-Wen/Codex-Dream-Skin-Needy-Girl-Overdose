import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import vm from "node:vm";
import { fileURLToPath } from "node:url";
import { SKIN_VERSION, verifySession, waitForVerifiedSession } from "../scripts/injector.mjs";

const here = path.dirname(fileURLToPath(import.meta.url));
const selectorContract = JSON.parse(fs.readFileSync(
  path.resolve(here, "../assets/selectors.json"),
  "utf8",
));
const selectorFor = (key) => selectorContract.selectors.find((entry) => entry.key === key)?.selector;
const selectors = {
  shell: selectorFor("shell-main"),
  sidebar: selectorFor("left-panel"),
  composer: selectorFor("composer-chrome"),
  home: selectorFor("home-route"),
  homeIcon: selectorFor("home-icon"),
  gameSource: selectorFor("game-source"),
  suggestions: selectorFor("home-suggestions"),
  settings: selectorFor("appearance-radio"),
  themePreview: '[data-testid="theme-preview"]',
};
for (const [key, selector] of Object.entries(selectors)) {
  assert.equal(typeof selector, "string", `missing selector fixture: ${key}`);
}

function makeRect(width = 800, height = 600, x = 0, y = 0) {
  return { x, y, width, height, right: x + width, bottom: y + height };
}

function makeElement({
  rect = makeRect(),
  style = {},
  checkVisibility = true,
  isConnected = true,
} = {}) {
  return {
    isConnected,
    classList: [],
    childNodes: [],
    textContent: "",
    _style: {
      display: "block",
      visibility: "visible",
      contentVisibility: "visible",
      opacity: "1",
      color: "rgb(0, 0, 0)",
      ...style,
    },
    getBoundingClientRect: () => rect,
    getAttribute: () => null,
    checkVisibility: () => checkVisibility,
    closest: () => null,
    querySelector: () => null,
    querySelectorAll: () => [],
  };
}

function makeDomFixture({
  scope = { level: "L1", baseState: "thread", missingL1: [] },
  shell = makeElement(),
  sidebar = makeElement(),
  composer = makeElement(),
  shellCandidates = [shell],
  sidebarCandidates = [sidebar],
  composerCandidates = [composer],
  settings = null,
  visibilityState = "visible",
  viewportWidth = 1280,
  viewportHeight = 800,
} = {}) {
  const styleNode = {};
  const documentElement = {
    scrollWidth: viewportWidth,
    clientWidth: viewportWidth,
    scrollHeight: viewportHeight,
    clientHeight: viewportHeight,
    getAttribute: (name) => name === "data-dream-skin" ? "active" : null,
  };
  const document = {
    documentElement,
    adoptedStyleSheets: [],
    visibilityState,
    querySelector(selector) {
      if (selector === selectors.shell) return shellCandidates[0] ?? null;
      if (selector === selectors.sidebar) return sidebarCandidates[0] ?? null;
      if (selector === selectors.composer) return composerCandidates[0] ?? null;
      if (selector === selectors.settings || selector === selectors.themePreview) return settings;
      if (selector === selectors.home || selector === selectors.homeIcon ||
          selector === selectors.gameSource || selector === selectors.suggestions) return null;
      return null;
    },
    querySelectorAll(selector) {
      if (selector === selectors.shell) return shellCandidates;
      if (selector === selectors.sidebar) return sidebarCandidates;
      if (selector === selectors.composer) return composerCandidates;
      if (selector === selectors.settings || selector === selectors.themePreview) {
        return settings ? [settings] : [];
      }
      return [];
    },
    getElementById: (id) => id === "codex-dream-skin-style" ? styleNode : null,
  };
  const window = {
    __CODEX_DREAM_SKIN_STATE__: {
      version: SKIN_VERSION,
      themeId: "fixture-theme",
      revision: "fixture-revision",
      styleMode: "style",
      styleNode,
      scope,
    },
  };
  return {
    document,
    window,
    innerWidth: viewportWidth,
    innerHeight: viewportHeight,
    getComputedStyle: (node) => node?._style ?? {},
  };
}

function makeSession({
  dom = makeDomFixture(),
  evaluateErrors = [],
  nativeResponse = {
    windowId: 41,
    bounds: { width: 1280, height: 800, windowState: "normal" },
  },
} = {}) {
  let evaluateCount = 0;
  return {
    target: { id: "page-main" },
    get evaluateCount() { return evaluateCount; },
    async evaluate(expression) {
      const error = evaluateErrors[evaluateCount];
      evaluateCount += 1;
      if (error) throw error;
      return vm.runInNewContext(expression, dom);
    },
    async send(method, params) {
      assert.equal(method, "Browser.getWindowForTarget");
      assert.deepEqual(params, { targetId: "page-main" });
      return nativeResponse;
    },
  };
}

async function verify(overrides = {}) {
  return verifySession(
    makeSession(overrides),
    "fixture-theme",
    "fixture-revision",
  );
}

test("visible L1 renderer passes exact macOS verification", async () => {
  const result = await verify();
  assert.equal(result.pass, true);
  assert.equal(result.shell.visible, true);
  assert.equal(result.sidebar.visible, true);
  assert.equal(result.composer.visible, true);
});

test("CSS-hidden, detached, and offscreen anchors cannot satisfy L1", async () => {
  const cases = [
    ["display none", makeElement({ style: { display: "none" } })],
    ["visibility hidden", makeElement({ style: { visibility: "hidden" } })],
    ["visibility collapse", makeElement({ style: { visibility: "collapse" } })],
    ["content-visibility hidden", makeElement({ style: { contentVisibility: "hidden" } })],
    ["opacity zero", makeElement({ style: { opacity: "0" } })],
    ["opacity threshold", makeElement({ style: { opacity: ".05" } })],
    ["checkVisibility false", makeElement({ checkVisibility: false })],
    ["detached", makeElement({ isConnected: false })],
    ["offscreen right", makeElement({ rect: makeRect(200, 200, 1280, 20) })],
    ["offscreen left", makeElement({ rect: makeRect(200, 200, -200, 20) })],
    ["offscreen below", makeElement({ rect: makeRect(200, 200, 20, 800) })],
  ];

  for (const [label, shell] of cases) {
    const result = await verify({ dom: makeDomFixture({ shell }) });
    assert.equal(result.pass, false, label);
    assert.equal(result.checks.structurePass, false, label);
    assert.equal(result.shell?.visible ?? false, false, label);
  }
});

test("visibility scans past stale candidates and accepts opacity above the shared threshold", async () => {
  const hidden = makeElement({ style: { opacity: ".05" } });
  const visible = makeElement({ style: { opacity: ".051" } });
  const result = await verify({
    dom: makeDomFixture({
      shellCandidates: [hidden, visible],
      sidebarCandidates: [hidden, visible],
      composerCandidates: [hidden, visible],
    }),
  });
  assert.equal(result.pass, true);
  assert.equal(result.shell.visible, true);
  assert.equal(result.sidebar.visible, true);
  assert.equal(result.composer.visible, true);
});

test("transient Runtime.evaluate failures are retried inside the bounded deadline", async () => {
  const session = makeSession({
    evaluateErrors: [new Error("Execution context was destroyed during navigation")],
  });
  const result = await waitForVerifiedSession(
    session,
    100,
    "fixture-theme",
    "fixture-revision",
    1,
  );
  assert.equal(result.pass, true);
  assert.equal(session.evaluateCount, 2);
});

test("verification rethrows the last transient error when no sample succeeds", async () => {
  const session = makeSession();
  session.evaluate = async () => {
    throw new Error("Execution context stayed unavailable");
  };
  await assert.rejects(
    waitForVerifiedSession(session, 15, "fixture-theme", "fixture-revision", 1),
    /Execution context stayed unavailable/,
  );
});
