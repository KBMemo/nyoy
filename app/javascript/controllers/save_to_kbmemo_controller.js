import { Controller } from "@hotwired/stimulus"

// Turbo Stream updates render forms without the browser session, so embedded
// authenticity_token values are invalid. Always submit with the meta tag token.
export default class extends Controller {
  static values = { url: String }

  async save(event) {
    event.preventDefault()

    const button = this.element
    if (button.disabled) return

    if (!this.hasUrlValue || !this.urlValue) {
      alert("保存先 URL が設定されていません。ページを再読み込みしてから再度お試しください。")
      return
    }

    const token = this.csrfToken
    if (!token) {
      alert("セッションが無効です。ページを再読み込みしてから再度お試しください。")
      return
    }

    const originalText = button.textContent
    button.disabled = true
    button.textContent = "保存中…"

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          "X-CSRF-Token": token,
          Accept: "application/json"
        },
        credentials: "same-origin"
      })

      const payload = await response.json()
      if (!response.ok || !payload.ok) {
        throw new Error(payload.error || "保存に失敗しました")
      }

      button.textContent = "徒然に保存済み"

      if (payload.url) {
        window.open(payload.url, "_blank", "noopener")
      }

      if (payload.notice) {
        alert(payload.notice)
      }
    } catch (error) {
      button.disabled = false
      button.textContent = originalText
      alert(error.message)
    }
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
