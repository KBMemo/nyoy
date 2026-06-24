import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["elapsed"]
  static values = {
    startedAt: String,
    finishedAt: String,
    active: Boolean
  }

  connect() {
    this.render()
    if (this.activeValue) {
      this.timer = window.setInterval(() => this.render(), 1000)
    }
  }

  disconnect() {
    if (this.timer) window.clearInterval(this.timer)
  }

  render() {
    if (!this.hasElapsedTarget || !this.startedAtValue) return

    const started = Date.parse(this.startedAtValue)
    if (Number.isNaN(started)) return

    const finished = this.activeValue ? Date.now() : Date.parse(this.finishedAtValue)
    const end = Number.isNaN(finished) ? Date.now() : finished
    const seconds = Math.max(0, (end - started) / 1000)

    this.elapsedTarget.textContent = this.formatDuration(seconds)
  }

  formatDuration(seconds) {
    if (seconds < 60) return `${seconds.toFixed(1)}秒`

    const minutes = Math.floor(seconds / 60)
    const remainder = seconds % 60
    return `${minutes}分${remainder.toFixed(0)}秒`
  }
}
