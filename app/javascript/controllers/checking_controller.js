import { Controller } from "@hotwired/stimulus"

// Owns the "checking" modal: no close button by design, closes only
// programmatically — on verdict-stream replace, or after the delay fallback.
// The verdict target holds the my_verdict chip; Turbo Stream replaces it in
// place when Attempt#broadcast_verdict_change fires.
export default class extends Controller {
  static targets = ["message", "verdict"]
  static values = {
    pending: String,
    delayed: String,
    // 3-minute fallback (spec section 3): swap text, then auto-close.
    timeout: { type: Number, default: 180000 }
  }

  connect() {
    this.onCancel = (event) => {
      if (this.pending()) event.preventDefault()
    }
    this.element.addEventListener("cancel", this.onCancel)
    this.observer = new MutationObserver(() => {
      if (!this.pending()) this.element.close()
    })
    this.observer.observe(this.verdictTarget, { childList: true, characterData: true, subtree: true })
    // Verdict already landed before connect (revisit with ?checking=): close now.
    if (!this.pending()) {
      this.element.close()
      return
    }
    this.timer = setTimeout(() => {
      if (this.pending()) {
        this.messageTarget.textContent = this.delayedValue
        this.element.close()
      }
    }, this.timeoutValue)
  }

  disconnect() {
    clearTimeout(this.timer)
    this.observer?.disconnect()
    this.element.removeEventListener("cancel", this.onCancel)
  }

  pending() {
    return this.verdictTarget.textContent.trim() === this.pendingValue
  }
}
