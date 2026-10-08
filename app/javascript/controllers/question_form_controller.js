import { Controller } from "@hotwired/stimulus"

// Owns the question form: type sync, option rows, deadline zone.
// Inline scripts do not run reliably on Turbo re-renders; connect() always does.
export default class extends Controller {
  static targets = ["type", "options", "reference", "codelangs", "examples", "list", "add", "deadline"]

  connect() {
    this.sync()
    this.reindex()
    this.showLocalDeadline()
  }

  // Options and reference visibility follows the answer type.
  sync() {
    const type = this.typeTarget.value
    const choice = type === "single_choice" || type === "multiple_choice"
    this.optionsTarget.hidden = !choice
    this.referenceTarget.hidden = choice
    this.codelangsTarget.hidden = type !== "code"
    this.examplesTarget.hidden = type !== "code"
  }

  // Dynamic option rows: 2 min, 8 max. Reindex keeps checkbox values
  // aligned with text order so parse_options zips correctly.
  add() {
    const rows = this.rows()
    if (rows.length >= 8) return
    const clone = rows.at(-1).cloneNode(true)
    clone.querySelector('input[type="text"]').value = ""
    clone.querySelector('input[type="checkbox"]').checked = false
    this.listTarget.appendChild(clone)
    this.reindex()
    this.listTarget.lastElementChild.querySelector('input[type="text"]').focus()
  }

  remove(event) {
    if (this.rows().length <= 2) return
    event.target.closest(".qf-opt-row").remove()
    this.reindex()
  }

  // datetime-local carries no zone; server speaks UTC. Show local wall, send UTC back.
  showLocalDeadline() {
    const el = this.deadlineTarget
    if (!el.value) return
    const asUTC = new Date(el.value + "Z")
    if (!isNaN(asUTC)) el.value = this.wall(asUTC, false)
  }

  toUTC() {
    const el = this.deadlineTarget
    const local = new Date(el.value)
    if (!isNaN(local)) el.value = this.wall(local, true)
  }

  rows() {
    return [...this.listTarget.querySelectorAll(".qf-opt-row")]
  }

  reindex() {
    const rows = this.rows()
    rows.forEach((row, idx) => {
      const text = row.querySelector('input[type="text"]')
      const check = row.querySelector('input[type="checkbox"]')
      if (text) { text.placeholder = `Вариант ${idx + 1}`; text.setAttribute("aria-label", `Вариант ${idx + 1}`) }
      if (check) check.value = idx
      const rm = row.querySelector(".qf-opt-remove")
      if (rm) rm.hidden = rows.length <= 2
    })
    this.addTarget.hidden = rows.length >= 8
  }

  wall(d, utc) {
    const pad = (n) => String(n).padStart(2, "0")
    const Y = utc ? d.getUTCFullYear() : d.getFullYear()
    const M = pad((utc ? d.getUTCMonth() : d.getMonth()) + 1)
    const D = pad(utc ? d.getUTCDate() : d.getDate())
    const h = pad(utc ? d.getUTCHours() : d.getHours())
    const m = pad(utc ? d.getUTCMinutes() : d.getMinutes())
    const s = pad(utc ? d.getUTCSeconds() : d.getSeconds())
    return `${Y}-${M}-${D}T${h}:${m}:${s}`
  }
}
