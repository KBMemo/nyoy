import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["submit", "status"]

  connect() {
    this.onSubmit = this.onSubmit.bind(this)
    this.element.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.onSubmit)
  }

  onSubmit() {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = true
      this.submitTarget.textContent = "解析中…"
    }

    if (this.hasStatusTarget) {
      this.statusTarget.classList.remove("hidden")
    }
  }
}
