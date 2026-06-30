import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    url: String,
    redirectUrl: String,
    interval: { type: Number, default: 1500 }
  }

  connect() {
    this.poll()
    this.timer = window.setInterval(() => this.poll(), this.intervalValue)
  }

  disconnect() {
    this.stopPolling()
  }

  async poll() {
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) return

      const data = await response.json()
      if (data.finished) {
        this.stopPolling()
        window.Turbo.visit(this.redirectUrlValue)
      }
    } catch (_error) {
      // Keep polling through transient network errors.
    }
  }

  stopPolling() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }
}
