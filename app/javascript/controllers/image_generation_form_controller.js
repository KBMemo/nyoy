import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "japanesePrompt",
    "sdPrompt",
    "styleId",
    "insertSdPromptButton",
    "replaceSdPromptButton",
    "translateStatus"
  ]
  static values = {
    translateUrl: String
  }

  connect() {
    this.updateReplaceButtonVisibility()
  }

  sdPromptInput() {
    this.updateReplaceButtonVisibility()
  }

  async generateSdPrompt(event) {
    event.preventDefault()

    const mode = event.params.mode
    const japanesePrompt = this.japanesePromptTarget.value.trim()
    if (!japanesePrompt) {
      this.showTranslateStatus("日本語プロンプトを入力してください", true)
      return
    }

    this.setTranslating(true)
    this.showTranslateStatus("SD プロンプトを生成中…")

    try {
      const prompt = await this.fetchTranslatedPrompt(japanesePrompt)
      this.applyPrompt(prompt, mode)
      this.showTranslateStatus(mode === "insert" ? "SD プロンプトを挿入しました" : "SD プロンプトを置き換えました")
    } catch (error) {
      this.showTranslateStatus(error.message, true)
    } finally {
      this.setTranslating(false)
    }
  }

  applyPrompt(prompt, mode) {
    const current = this.sdPromptTarget.value.trim()

    if (mode === "insert" && current) {
      this.sdPromptTarget.value = `${current}, ${prompt}`
    } else {
      this.sdPromptTarget.value = prompt
    }

    this.updateReplaceButtonVisibility()
  }

  async fetchTranslatedPrompt(japanesePrompt) {
    const response = await fetch(this.translateUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({
        japanese_prompt: japanesePrompt,
        style_id: this.styleId
      })
    })

    const payload = await response.json()
    if (!response.ok) {
      throw new Error(payload.error || "SD プロンプトの生成に失敗しました")
    }

    return payload.prompt
  }

  setTranslating(active) {
    this.promptButtons().forEach((button) => {
      button.disabled = active
    })

    if (this.hasInsertSdPromptButtonTarget) {
      this.insertSdPromptButtonTarget.textContent = active ? "生成中…" : "挿入"
    }
  }

  updateReplaceButtonVisibility() {
    if (!this.hasReplaceSdPromptButtonTarget) return

    const hasPrompt = this.sdPromptTarget.value.trim().length > 0
    this.replaceSdPromptButtonTarget.classList.toggle("hidden", !hasPrompt)
  }

  showTranslateStatus(message, isError = false) {
    if (!this.hasTranslateStatusTarget) return

    this.translateStatusTarget.textContent = message
    this.translateStatusTarget.classList.toggle("kb-text-muted", !isError)
    this.translateStatusTarget.classList.toggle("text-red-600", isError)
  }

  promptButtons() {
    return [
      this.hasInsertSdPromptButtonTarget ? this.insertSdPromptButtonTarget : null,
      this.hasReplaceSdPromptButtonTarget ? this.replaceSdPromptButtonTarget : null
    ].filter(Boolean)
  }

  get styleId() {
    if (!this.hasStyleIdTarget) return ""

    return this.styleIdTarget.value
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
