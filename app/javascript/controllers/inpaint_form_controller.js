import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["note", "promptDelta", "translateStatus", "translateElapsed"]
  static values = {
    translateUrl: String
  }

  async translateNote(event) {
    event.preventDefault()

    const note = this.noteTarget.value.trim()
    if (!note) {
      this.showStatus("修正指示を入力してください", true)
      return
    }

    this.setTranslating(true)
    this.showStatus("英語プロンプトを生成中…")

    try {
      const data = await this.fetchTranslation(note)
      this.promptDeltaTarget.value = data.translated_note
      if (data.translated) {
        this.showStatus("差分プロンプト欄に反映しました。必要なら編集してください。")
      } else {
        this.showStatus("英語のため差分プロンプト欄にそのまま反映しました。")
      }
    } catch (error) {
      this.showStatus(error.message, true)
    } finally {
      this.setTranslating(false)
    }
  }

  noteInput() {
    if (this.hasTranslateStatusTarget) {
      this.translateStatusTarget.textContent = ""
    }
    this.clearTranslateElapsed()
  }

  disconnect() {
    this.stopTranslateTimer()
  }

  async fetchTranslation(note) {
    const response = await fetch(this.translateUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({ inpaint_note: note })
    })

    const data = await response.json()
    if (!response.ok) {
      throw new Error(data.error || "翻訳に失敗しました")
    }

    return data
  }

  setTranslating(active) {
    this.element.querySelectorAll("[data-inpaint-form-translate-button]").forEach((button) => {
      button.disabled = active
    })

    if (active) {
      this.startTranslateTimer()
    } else {
      this.stopTranslateTimer()
    }
  }

  startTranslateTimer() {
    this.stopTranslateTimer()
    this.translateStartedAt = Date.now()
    this.renderTranslateElapsed()
    this.translateTimer = window.setInterval(() => this.renderTranslateElapsed(), 100)
  }

  stopTranslateTimer() {
    if (!this.translateTimer) return

    window.clearInterval(this.translateTimer)
    this.translateTimer = null
    this.renderTranslateElapsed()
  }

  clearTranslateElapsed() {
    this.stopTranslateTimer()
    this.translateStartedAt = null
    if (this.hasTranslateElapsedTarget) {
      this.translateElapsedTarget.textContent = ""
    }
  }

  renderTranslateElapsed() {
    if (!this.hasTranslateElapsedTarget || !this.translateStartedAt) return

    const seconds = Math.max(0, (Date.now() - this.translateStartedAt) / 1000)
    this.translateElapsedTarget.textContent = this.formatDuration(seconds)
  }

  formatDuration(seconds) {
    if (seconds < 60) return `${seconds.toFixed(1)}秒`

    const minutes = Math.floor(seconds / 60)
    const remainder = seconds % 60
    return `${minutes}分${remainder.toFixed(0)}秒`
  }

  showStatus(message, isError = false) {
    if (!this.hasTranslateStatusTarget) return

    this.translateStatusTarget.textContent = message
    this.translateStatusTarget.classList.toggle("kb-text-danger", isError)
    this.translateStatusTarget.classList.toggle("kb-text-muted", !isError)
  }

  get csrfToken() {
    return document.querySelector("meta[name='csrf-token']")?.content
  }
}
