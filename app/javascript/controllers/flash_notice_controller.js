import { Controller } from "@hotwired/stimulus"

const TOAST_BASE =
  "pointer-events-auto flex items-start gap-2 rounded-md border px-3 py-2 text-sm shadow-md transition-all duration-200 ease-out"
const DISMISS_BASE =
  "shrink-0 rounded p-0.5 text-base leading-none opacity-60 hover:opacity-100 kb-flash-dismiss"

export default class extends Controller {
  static targets = ["live", "message"]

  static values = {
    dismissAfter: { type: Number, default: 6000 }
  }

  connect() {
    this.messageTargets.forEach((el) => this.arm(el))
  }

  disconnect() {
    this.messageTargets.forEach((el) => this.clearTimer(el))
  }

  dismiss(event) {
    event.preventDefault()
    const el = event.currentTarget.closest("[data-flash-notice-target='message']")
    if (el) this.removeMessage(el)
  }

  arm(el) {
    this.clearTimer(el)
    el._flashDismissTimer = window.setTimeout(() => {
      this.removeMessage(el)
    }, this.dismissAfterValue)
  }

  clearTimer(el) {
    if (!el?._flashDismissTimer) return
    window.clearTimeout(el._flashDismissTimer)
    el._flashDismissTimer = null
  }

  removeMessage(el) {
    this.clearTimer(el)
    el.classList.add("opacity-0", "translate-x-2", "pointer-events-none")
    window.setTimeout(() => el.remove(), 200)
  }
}
