import "@hotwired/turbo-rails"
import { blobatarUri } from "blobatar/uri"

// Initials are the server-rendered fallback; this swaps in the deterministic blobatar.
// ponytail: rescans the document on every DOM mutation because Turbo stream appends
// (comments paging) fire no page-level event; switch to explicit events if profiles grow.
const drawBlobatars = () => {
  document.querySelectorAll("[data-blobatar]:not([data-blobatar-drawn])").forEach((el) => {
    el.dataset.blobatarDrawn = "";
    el.style.backgroundImage = `url("${blobatarUri(el.dataset.blobatar, { background: "circle" })}")`;
    el.textContent = "";
  });
};

drawBlobatars();
new MutationObserver(drawBlobatars).observe(document.documentElement, { childList: true, subtree: true });