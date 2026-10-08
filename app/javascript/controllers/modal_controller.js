import { Controller } from "@hotwired/stimulus"
// Closes the wrapping <details> modal (cancel buttons).
export default class extends Controller {
  close(event) {
    event.currentTarget.closest("details")?.removeAttribute("open")
  }
}
