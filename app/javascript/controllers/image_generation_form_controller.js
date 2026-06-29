import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "japanesePrompt",
    "sdPrompt",
    "negativePrompt",
    "styleId",
    "aspectRatio",
    "insertSdPromptButton",
    "replaceSdPromptButton",
    "insertNegativePromptButton",
    "replaceNegativePromptButton",
    "translateStatus",
    "negativeTranslateStatus"
  ]
  static values = {
    translateUrl: String
  }

  connect() {
    this.updateReplaceButtonVisibility()
    this.updateNegativeReplaceButtonVisibility()
  }

  sdPromptInput() {
    this.updateReplaceButtonVisibility()
  }

  negativePromptInput() {
    this.updateNegativeReplaceButtonVisibility()
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
    this.showTranslateStatus("翻訳プロンプトを生成中…")

    try {
      const { prompt } = await this.fetchTranslatedPlan(japanesePrompt)
      this.applyPrompt(prompt, mode)
      this.showTranslateStatus(mode === "insert" ? "翻訳プロンプトを挿入しました" : "翻訳プロンプトに置き換えました")
    } catch (error) {
      this.showTranslateStatus(error.message, true)
    } finally {
      this.setTranslating(false)
    }
  }

  async generateNegativePrompt(event) {
    event.preventDefault()

    const mode = event.params.mode
    const japanesePrompt = this.japanesePromptTarget.value.trim()
    if (!japanesePrompt) {
      this.showNegativeTranslateStatus("日本語プロンプトを入力してください", true)
      return
    }

    this.setTranslating(true)
    this.showNegativeTranslateStatus("ネガティブプロンプトを生成中…")

    try {
      const { negative_prompt: negativePrompt } = await this.fetchTranslatedPlan(japanesePrompt)
      this.applyNegativePrompt(negativePrompt, mode)
      this.showNegativeTranslateStatus(
        mode === "insert" ? "ネガティブプロンプトを挿入しました" : "ネガティブプロンプトに置き換えました"
      )
    } catch (error) {
      this.showNegativeTranslateStatus(error.message, true)
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

  applyNegativePrompt(negativePrompt, mode) {
    const current = this.negativePromptTarget.value.trim()

    if (mode === "insert" && current) {
      this.negativePromptTarget.value = `${current}, ${negativePrompt}`
    } else {
      this.negativePromptTarget.value = negativePrompt
    }

    this.updateNegativeReplaceButtonVisibility()
  }

  async fetchTranslatedPlan(japanesePrompt) {
    const response = await fetch(this.translateUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({
        japanese_prompt: japanesePrompt,
        style_id: this.styleId,
        aspect_ratio: this.aspectRatio
      })
    })

    const payload = await response.json()
    if (!response.ok) {
      throw new Error(payload.error || "プロンプトの生成に失敗しました")
    }

    return payload
  }

  setTranslating(active) {
    this.promptButtons().forEach((button) => {
      button.disabled = active
    })
    this.negativePromptButtons().forEach((button) => {
      button.disabled = active
    })

    if (this.hasInsertSdPromptButtonTarget) {
      this.insertSdPromptButtonTarget.textContent = active ? "生成中…" : "翻訳挿入"
    }
    if (this.hasInsertNegativePromptButtonTarget) {
      this.insertNegativePromptButtonTarget.textContent = active ? "生成中…" : "翻訳挿入"
    }
  }

  updateReplaceButtonVisibility() {
    if (!this.hasReplaceSdPromptButtonTarget) return

    const hasPrompt = this.sdPromptTarget.value.trim().length > 0
    this.replaceSdPromptButtonTarget.classList.toggle("hidden", !hasPrompt)
  }

  updateNegativeReplaceButtonVisibility() {
    if (!this.hasReplaceNegativePromptButtonTarget) return

    const hasPrompt = this.negativePromptTarget.value.trim().length > 0
    this.replaceNegativePromptButtonTarget.classList.toggle("hidden", !hasPrompt)
  }

  showTranslateStatus(message, isError = false) {
    if (!this.hasTranslateStatusTarget) return

    this.translateStatusTarget.textContent = message
    this.translateStatusTarget.classList.toggle("kb-text-muted", !isError)
    this.translateStatusTarget.classList.toggle("text-red-600", isError)
  }

  showNegativeTranslateStatus(message, isError = false) {
    if (!this.hasNegativeTranslateStatusTarget) return

    this.negativeTranslateStatusTarget.textContent = message
    this.negativeTranslateStatusTarget.classList.toggle("kb-text-muted", !isError)
    this.negativeTranslateStatusTarget.classList.toggle("text-red-600", isError)
  }

  promptButtons() {
    return [
      this.hasInsertSdPromptButtonTarget ? this.insertSdPromptButtonTarget : null,
      this.hasReplaceSdPromptButtonTarget ? this.replaceSdPromptButtonTarget : null
    ].filter(Boolean)
  }

  negativePromptButtons() {
    return [
      this.hasInsertNegativePromptButtonTarget ? this.insertNegativePromptButtonTarget : null,
      this.hasReplaceNegativePromptButtonTarget ? this.replaceNegativePromptButtonTarget : null
    ].filter(Boolean)
  }

  get styleId() {
    if (!this.hasStyleIdTarget) return ""

    return this.styleIdTarget.value
  }

  get aspectRatio() {
    if (!this.hasAspectRatioTarget) return ""

    return this.aspectRatioTarget.value
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
