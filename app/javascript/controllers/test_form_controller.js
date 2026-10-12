import { Controller } from "@hotwired/stimulus"

// Owns the test creation list: question blocks append below, each with its
// own points; everything publishes at once. Same clone-and-reindexReflex as
// question-form#add; order in DOM is the position (parallel arrays).
export default class extends Controller {
  static targets = ["list", "template", "add"]

  connect() {
    this.reindex()
  }

  // Clone the blank template, append, focus its title.
  add() {
    const clone = this.templateTarget.content.firstElementChild.cloneNode(true)
    this.listTarget.appendChild(clone)
    this.reindex()
    const title = this.listTarget.lastElementChild.querySelector('input[name="questions_title[]"]')
    if (title) title.focus()
  }

  remove(event) {
    event.target.closest("fieldset").remove()
    this.reindex()
  }

  blocks() {
    return [...this.listTarget.querySelectorAll("fieldset")]
  }

  reindex() {
    this.blocks().forEach((block, idx) => {
      const n = idx + 1
      const head = block.querySelector("[data-role='head']")
      if (head) head.textContent = `Вопрос ${n}`
      block.querySelectorAll("[data-role='label']").forEach((el) => {
        const base = el.getAttribute("data-base")
        if (base) el.setAttribute("aria-label", `${base} ${n}`)
      })
    })
  }
}
