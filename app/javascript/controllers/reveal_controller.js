import { Controller } from "@hotwired/stimulus"

// Reloads the answers frame once at the deadline, revealing reference,
// attempts, and verdicts without a page reload. No server event fires
// exactly at the deadline, so the client owns the timer.
export default class extends Controller {
  static values = { deadline: String, url: String }

  connect() {
    const ms = new Date(this.deadlineValue) - Date.now()
    if (ms <= 0 || ms > 2147483647) return
    this.timer = setTimeout(() => { this.element.src = this.urlValue }, ms)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}
