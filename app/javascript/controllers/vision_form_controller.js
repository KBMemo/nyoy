import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit", "status", "resultPanel", "resultText", "error"]

  async submit(event) {
    event.preventDefault()

    const form = event.currentTarget
    this.setLoading(true)
    this.clearError()

    try {
      const response = await fetch(form.action, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: new FormData(form)
      })

      const data = await response.json()

      if (!response.ok) {
        this.showError(data.error || "解析に失敗しました")
        return
      }

      this.showResult(data.result)
      form.querySelector("#image")?.removeAttribute("required")
    } catch (_error) {
      this.showError("解析に失敗しました")
    } finally {
      this.setLoading(false)
    }
  }

  showResult(text) {
    this.resultTextTarget.textContent = text
    this.resultPanelTarget.classList.remove("hidden")
    this.resultPanelTarget.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  showError(message) {
    this.errorTarget.textContent = message
    this.errorTarget.classList.remove("hidden")
  }

  clearError() {
    this.errorTarget.textContent = ""
    this.errorTarget.classList.add("hidden")
  }

  setLoading(loading) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = loading
      this.submitTarget.textContent = loading ? "解析中…" : "解析する"
    }

    if (this.hasStatusTarget) {
      this.statusTarget.classList.toggle("hidden", !loading)
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
