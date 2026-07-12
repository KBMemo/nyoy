import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "japanesePrompt",
    "sdPrompt",
    "negativePrompt",
    "styleId",
    "aspectRatio",
    "stylePlanConnectionKey",
    "sdModelProfileId",
    "sdPromptTemplateId",
    "insertSdPromptButton",
    "replaceSdPromptButton",
    "insertNegativePromptButton",
    "replaceNegativePromptButton",
    "translateStatus",
    "negativeTranslateStatus",
    "directSdPrompt",
    "directNegativePrompt",
    "directInsertSdPromptButton",
    "directReplaceSdPromptButton",
    "directInsertNegativePromptButton",
    "directReplaceNegativePromptButton",
    "directTranslateStatus",
    "directNegativeTranslateStatus"
  ]
  static values = {
    translateUrl: String,
    directGenerateUrl: String
  }

  connect() {
    this.updateReplaceButtonVisibility("draft")
    this.updateReplaceButtonVisibility("direct")
    this.updateNegativeReplaceButtonVisibility("draft")
    this.updateNegativeReplaceButtonVisibility("direct")
  }

  sdPromptInput() {
    this.updateReplaceButtonVisibility("draft")
  }

  directSdPromptInput() {
    this.updateReplaceButtonVisibility("direct")
  }

  negativePromptInput() {
    this.updateNegativeReplaceButtonVisibility("draft")
  }

  directNegativePromptInput() {
    this.updateNegativeReplaceButtonVisibility("direct")
  }

  async generateSdPrompt(event) {
    event.preventDefault()

    const mode = event.params.mode
    const flow = event.params.flow || "draft"
    const japanesePrompt = this.japanesePromptTarget.value.trim()
    if (!japanesePrompt) {
      this.showTranslateStatus("日本語プロンプトを入力してください", true, flow)
      return
    }

    this.setTranslating(true, flow)
    this.showTranslateStatus(this.generatingMessage(flow), false, flow)

    try {
      const { prompt } = await this.fetchPrompt(japanesePrompt, flow)
      this.applyPrompt(prompt, mode, flow)
      this.showTranslateStatus(this.appliedPromptMessage(mode, flow), false, flow)
    } catch (error) {
      this.showTranslateStatus(error.message, true, flow)
    } finally {
      this.setTranslating(false, flow)
    }
  }

  async generateNegativePrompt(event) {
    event.preventDefault()

    const mode = event.params.mode
    const flow = event.params.flow || "draft"
    const japanesePrompt = this.japanesePromptTarget.value.trim()
    if (!japanesePrompt) {
      this.showNegativeTranslateStatus("日本語プロンプトを入力してください", true, flow)
      return
    }

    this.setTranslating(true, flow)
    this.showNegativeTranslateStatus(this.generatingNegativeMessage(flow), false, flow)

    try {
      const { negative_prompt: negativePrompt } = await this.fetchPrompt(japanesePrompt, flow)
      this.applyNegativePrompt(negativePrompt, mode, flow)
      this.showNegativeTranslateStatus(this.appliedNegativeMessage(mode, flow), false, flow)
    } catch (error) {
      this.showNegativeTranslateStatus(error.message, true, flow)
    } finally {
      this.setTranslating(false, flow)
    }
  }

  applyPrompt(prompt, mode, flow) {
    const field = this.sdPromptField(flow)
    const current = field.value.trim()

    if (mode === "insert" && current) {
      field.value = `${current}, ${prompt}`
    } else {
      field.value = prompt
    }

    this.updateReplaceButtonVisibility(flow)
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }

  applyNegativePrompt(negativePrompt, mode, flow) {
    const field = this.negativePromptField(flow)
    const current = field.value.trim()

    if (mode === "insert" && current) {
      field.value = `${current}, ${negativePrompt}`
    } else {
      field.value = negativePrompt
    }

    this.updateNegativeReplaceButtonVisibility(flow)
    field.dispatchEvent(new Event("input", { bubbles: true }))
  }

  async fetchPrompt(japanesePrompt, flow) {
    if (flow === "direct") {
      return this.fetchDirectPrompt(japanesePrompt)
    }

    return this.fetchStylePlanPrompt(japanesePrompt)
  }

  async fetchStylePlanPrompt(japanesePrompt) {
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
        aspect_ratio: this.aspectRatio,
        style_plan_connection_key: this.stylePlanConnectionKey
      })
    })

    const payload = await this.parseJsonResponse(response)
    if (!response.ok) {
      throw new Error(payload.error || "プロンプトの生成に失敗しました")
    }

    return payload
  }

  async fetchDirectPrompt(japanesePrompt) {
    if (!this.hasDirectGenerateUrlValue || !this.directGenerateUrlValue) {
      throw new Error("直接生成 API が設定されていません")
    }

    if (!this.sdModelProfileId) {
      throw new Error("画像生成モデルを選択してください")
    }

    const response = await fetch(this.directGenerateUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken
      },
      body: JSON.stringify({
        japanese_prompt: japanesePrompt,
        sd_model_profile_id: this.sdModelProfileId,
        sd_prompt_template_id: this.sdPromptTemplateId,
        style_plan_connection_key: this.stylePlanConnectionKey
      })
    })

    const payload = await this.parseJsonResponse(response)
    if (!response.ok) {
      throw new Error(payload.error || "プロンプトの生成に失敗しました")
    }

    return payload
  }

  async parseJsonResponse(response) {
    const text = await response.text()
    if (!text.trim()) return {}

    try {
      return JSON.parse(text)
    } catch (_error) {
      throw new Error(text.trim() || "サーバーから不正な応答を受け取りました")
    }
  }

  setTranslating(active, flow = "draft") {
    this.promptButtons(flow).forEach((button) => {
      button.disabled = active
    })
    this.negativePromptButtons(flow).forEach((button) => {
      button.disabled = active
    })

    const insertLabel = flow === "direct" ? "生成挿入" : "翻訳挿入"
    const insertButton = flow === "direct" ? this.directInsertSdPromptButtonTarget : this.insertSdPromptButtonTarget
    const negativeInsertButton =
      flow === "direct" ? this.directInsertNegativePromptButtonTarget : this.insertNegativePromptButtonTarget

    if (insertButton) insertButton.textContent = active ? "生成中…" : insertLabel
    if (negativeInsertButton) negativeInsertButton.textContent = active ? "生成中…" : insertLabel
  }

  generatingMessage(flow) {
    return flow === "direct" ? "SD プロンプトを生成中…" : "翻訳プロンプトを生成中…"
  }

  generatingNegativeMessage(flow) {
    return flow === "direct" ? "ネガティブプロンプトを生成中…" : "ネガティブプロンプトを生成中…"
  }

  appliedPromptMessage(mode, flow) {
    const verb = flow === "direct" ? "生成" : "翻訳"
    return mode === "insert" ? `${verb}プロンプトを挿入しました` : `${verb}プロンプトに置き換えました`
  }

  appliedNegativeMessage(mode, flow) {
    return mode === "insert" ? "ネガティブプロンプトを挿入しました" : "ネガティブプロンプトに置き換えました"
  }

  updateReplaceButtonVisibility(flow) {
    const replaceButton = flow === "direct" ? this.directReplaceSdPromptButtonTarget : this.replaceSdPromptButtonTarget
    if (!replaceButton) return

    const hasPrompt = this.sdPromptField(flow).value.trim().length > 0
    replaceButton.classList.toggle("hidden", !hasPrompt)
  }

  updateNegativeReplaceButtonVisibility(flow) {
    const replaceButton =
      flow === "direct" ? this.directReplaceNegativePromptButtonTarget : this.replaceNegativePromptButtonTarget
    if (!replaceButton) return

    const hasPrompt = this.negativePromptField(flow).value.trim().length > 0
    replaceButton.classList.toggle("hidden", !hasPrompt)
  }

  showTranslateStatus(message, isError = false, flow = "draft") {
    const statusTarget = flow === "direct" ? this.directTranslateStatusTarget : this.translateStatusTarget
    if (!statusTarget) return

    statusTarget.textContent = message
    statusTarget.classList.toggle("kb-text-muted", !isError)
    statusTarget.classList.toggle("text-red-600", isError)
  }

  showNegativeTranslateStatus(message, isError = false, flow = "draft") {
    const statusTarget =
      flow === "direct" ? this.directNegativeTranslateStatusTarget : this.negativeTranslateStatusTarget
    if (!statusTarget) return

    statusTarget.textContent = message
    statusTarget.classList.toggle("kb-text-muted", !isError)
    statusTarget.classList.toggle("text-red-600", isError)
  }

  sdPromptField(flow) {
    return flow === "direct" ? this.directSdPromptTarget : this.sdPromptTarget
  }

  negativePromptField(flow) {
    return flow === "direct" ? this.directNegativePromptTarget : this.negativePromptTarget
  }

  promptButtons(flow) {
    if (flow === "direct") {
      return [this.directInsertSdPromptButtonTarget, this.directReplaceSdPromptButtonTarget].filter(Boolean)
    }

    return [this.insertSdPromptButtonTarget, this.replaceSdPromptButtonTarget].filter(Boolean)
  }

  negativePromptButtons(flow) {
    if (flow === "direct") {
      return [this.directInsertNegativePromptButtonTarget, this.directReplaceNegativePromptButtonTarget].filter(Boolean)
    }

    return [this.insertNegativePromptButtonTarget, this.replaceNegativePromptButtonTarget].filter(Boolean)
  }

  get styleId() {
    if (!this.hasStyleIdTarget) return ""

    return this.styleIdTarget.value
  }

  get aspectRatio() {
    if (!this.hasAspectRatioTarget) return ""

    return this.aspectRatioTarget.value
  }

  get stylePlanConnectionKey() {
    if (!this.hasStylePlanConnectionKeyTarget) return ""

    return this.stylePlanConnectionKeyTarget.value
  }

  get sdModelProfileId() {
    if (!this.hasSdModelProfileIdTarget) return ""

    return this.sdModelProfileIdTarget.value
  }

  get sdPromptTemplateId() {
    if (!this.hasSdPromptTemplateIdTarget) return ""

    return this.sdPromptTemplateIdTarget.value
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
