import { Controller } from "@hotwired/stimulus"

// Enter sends the comment, Shift+Enter keeps a newline.
// Replaces the inline onkeydown handler on the chat input.
export default class extends Controller {
  send(event) {
    if (event.key === "Enter" && !event.shiftKey) {
      event.preventDefault()
      this.element.form.requestSubmit()
    }
  }
}
