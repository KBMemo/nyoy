import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["elapsed"]
  static values = {
    startedAt: String,
    finishedAt: String,
    active: Boolean
  }

  connect() {
    this.startTimer()
  }

  disconnect() {
    this.stopTimer()
  }

  startedAtValueChanged() {
    this.render()
  }

  finishedAtValueChanged() {
    this.render()
  }

  activeValueChanged() {
    this.startTimer()
  }

  startTimer() {
    this.render()
    this.stopTimer()

    if (this.activeValue) {
      this.timer = window.setInterval(() => this.render(), 1000)
    }
  }

  stopTimer() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }

  render() {
    if (!this.hasElapsedTarget || !this.startedAtValue) return

    const started = Date.parse(this.startedAtValue)
    if (Number.isNaN(started)) return

    let end
    if (this.activeValue) {
      end = Date.now()
    } else {
      if (!this.finishedAtValue) return

      end = Date.parse(this.finishedAtValue)
      if (Number.isNaN(end)) return
    }

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
