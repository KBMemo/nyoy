import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit"]
  static values = {
    responding: { type: Boolean, default: false }
  }

  connect() {
    this.busy = this.respondingValue
    this.applySubmitState()
  }

  submit(event) {
    if (this.busy) {
      event.preventDefault()
      return
    }

    this.busy = true
    this.applySubmitState()
  }

  submitOnShortcut(event) {
    if (!(event.target instanceof HTMLTextAreaElement)) return
    if (event.key !== "Enter") return
    if (!event.ctrlKey && !event.metaKey) return
    if (event.isComposing) return

    event.preventDefault()
    if (this.busy) return

    this.element.requestSubmit()
  }

  applySubmitState() {
    if (!this.hasSubmitTarget) return

    this.submitTarget.disabled = this.busy
    this.submitTarget.value = this.busy ? "応答中…" : "送信"
  }
}
