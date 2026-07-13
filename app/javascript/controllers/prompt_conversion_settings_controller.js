import { Controller } from "@hotwired/stimulus"

// Fills prompt-conversion sampling fields from /props or a preset's params JSON.
export default class extends Controller {
  static targets = ["presetSelect", "status", "error", "loadButton"]
  static values = {
    loadUrl: String,
    fieldPrefix: { type: String, default: "service_connection_prompt_conversion_settings" }
  }

  async loadFromServer(event) {
    event.preventDefault()
    this.clearMessages()

    if (!this.loadUrlValue) {
      this.showError("保存後の接続でのみサーバーから読み込めます。")
      return
    }

    const button = this.hasLoadButtonTarget ? this.loadButtonTarget : event.currentTarget
    button.disabled = true
    const original = button.textContent
    button.textContent = "読み込み中…"

    try {
      const response = await fetch(this.loadUrlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        credentials: "same-origin"
      })
      const payload = await response.json().catch(() => ({}))
      if (!response.ok || !payload.ok) {
        throw new Error(payload.error || "読み込みに失敗しました")
      }

      this.applyParams(payload.sampling || {})
      this.showStatus(payload.message || "サーバー設定をフォームに反映しました")
    } catch (error) {
      this.showError(error.message)
    } finally {
      button.disabled = false
      button.textContent = original
    }
  }

  applyPreset(event) {
    event.preventDefault()
    this.clearMessages()

    const select = this.presetSelectTarget
    const option = select.selectedOptions[0]
    if (!option || !option.value) {
      this.showError("プリセットを選択してください。")
      return
    }

    let params = {}
    try {
      params = JSON.parse(option.dataset.params || "{}")
    } catch {
      this.showError("プリセットの読み込みに失敗しました。")
      return
    }

    this.applyParams(params)
    this.showStatus(`「${option.textContent}」をフォームに反映しました`)
  }

  applyParams(params) {
    Object.entries(params || {}).forEach(([key, value]) => {
      const field = this.fieldFor(key)
      if (!field) return

      if (value === null || value === undefined) {
        field.value = ""
        return
      }

      if (key === "enable_thinking") {
        field.value = String(value)
        return
      }

      field.value = value
    })
  }

  fieldFor(key) {
    return this.element.querySelector(`[data-prompt-conversion-settings-field="${key}"]`)
  }

  clearMessages() {
    if (this.hasStatusTarget) {
      this.statusTarget.classList.add("hidden")
      this.statusTarget.textContent = ""
    }
    if (this.hasErrorTarget) {
      this.errorTarget.classList.add("hidden")
      this.errorTarget.textContent = ""
    }
  }

  showStatus(message) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.classList.remove("hidden")
  }

  showError(message) {
    if (!this.hasErrorTarget) return
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
