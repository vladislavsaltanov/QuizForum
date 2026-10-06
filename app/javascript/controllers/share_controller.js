import { Controller } from "@hotwired/stimulus"

// Copies the page URL; replaces inline onclick clipboard handlers.
export default class extends Controller {
  copy() {
    navigator.clipboard?.writeText(location.href)
  }
}
