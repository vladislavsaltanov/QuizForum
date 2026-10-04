import "@hotwired/turbo-rails"
import { blobatar } from "blobatar"
import { _posed } from "blobatar/internal"

// Initials are the server-rendered fallback; this swaps in the blobatar as inline
// SVG and lets its eyes follow the pointer.
//
// Inline SVG is mandatory: a background data-URI is an isolated image and has no
// eye node to move. The eye group is located by the exact colour blobatar itself
// computed for this name (_posed().fill.eye), not by guessing at the markup.
//
// ponytail: _posed is an underscore-prefixed export. It is stable within 2.7.x but
// is not covered by semver; re-check this file when upgrading blobatar.
// ponytail: rescans the document on every DOM mutation because Turbo stream appends
// (comments paging) fire no page-level event; switch to explicit events if profiles grow.

const TRAVEL = 7;          // viewBox units — 1 unit ≈ 0.34–0.64 CSS px, so this is a ~3px shift
const RADIUS = 110;        // px; past this the avatar ignores the pointer entirely
const CENTRE_DEAD = 6;     // px; direction is meaningless this close to the middle

const watchers = [];

// Also prunes: a Turbo visit discards the old body, and its watchers would
// otherwise linger and keep being transformed forever.
const measure = () => {
  for (let i = watchers.length - 1; i >= 0; i--) {
    const w = watchers[i];
    if (!w.el.isConnected) { watchers.splice(i, 1); continue; }
    const r = w.el.getBoundingClientRect();
    w.cx = r.left + r.width / 2;
    w.cy = r.top + r.height / 2;
  }
};

const look = ({ clientX: x, clientY: y }) => watchers.forEach((w) => {
  const dx = x - w.cx, dy = y - w.cy;
  const d = Math.hypot(dx, dy);
  let shift = "translate(0px, 0px)";
  if (d > CENTRE_DEAD && d <= RADIUS) {
    const reach = TRAVEL * Math.min(1, d / RADIUS);
    shift = `translate(${(dx / d * reach).toFixed(2)}px, ${(dy / d * reach).toFixed(2)}px)`;
  }
  w.eyes.style.transform = shift;
});

const drawBlobatars = () => {
  document.querySelectorAll("[data-blobatar]:not([data-blobatar-drawn])").forEach((el) => {
    el.dataset.blobatarDrawn = "";
    const name = el.dataset.blobatar;
    const svg = new DOMParser()
      .parseFromString(blobatar(name, { background: "circle" }), "image/svg+xml")
      .documentElement;
    el.replaceChildren(svg);

    const eyes = svg.querySelector(`g[fill="${_posed(name).fill.eye}"]`);
    if (eyes) {
      eyes.classList.add("qf-blob-eyes");
      watchers.push({ el, eyes });
    }
  });
  measure();
};

drawBlobatars();
new MutationObserver(drawBlobatars).observe(document.documentElement, { childList: true, subtree: true });

if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
  document.addEventListener("pointermove", look, { passive: true });
  addEventListener("resize", measure, { passive: true });
  // Capture, not bubble: `scroll` does not bubble, and the comment thread is its
  // own scroll container — a window listener would miss every chat scroll and the
  // cached rects would go stale.
  document.addEventListener("scroll", measure, { passive: true, capture: true });
  // Web fonts land after first paint and shift every row.
  document.fonts?.ready.then(measure);
}