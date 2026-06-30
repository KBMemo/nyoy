import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["display", "image", "label", "hint"]

  connect() {
    this.previewUrl = null
    this.initialImageSrc = this.hasImageTarget ? this.imageTarget.getAttribute("src") : null
    this.initialLabel = this.hasLabelTarget ? this.labelTarget.textContent.trim() : ""
    this.initialHint = this.hasHintTarget ? this.hintTarget.textContent.trim() : ""

    if (this.initialImageSrc) {
      this.element.dispatchEvent(new CustomEvent("source-image:changed", {
        bubbles: true,
        detail: { url: this.initialImageSrc }
      }))
    }
  }

  disconnect() {
    this.revokePreviewUrl()
  }

  preview(event) {
    const file = event.target.files?.[0]
    this.revokePreviewUrl()

    if (!file) {
      this.restoreInitial()
      return
    }

    this.previewUrl = URL.createObjectURL(file)
    this.imageTarget.src = this.previewUrl
    this.imageTarget.alt = file.name
    this.displayTarget.hidden = false
    this.element.dispatchEvent(new CustomEvent("source-image:changed", {
      bubbles: true,
      detail: { url: this.previewUrl, file }
    }))

    if (this.hasLabelTarget) {
      this.labelTarget.hidden = true
    }

    if (this.hasHintTarget) {
      this.hintTarget.hidden = false
      this.hintTarget.textContent = "別の画像に差し替える場合は、下からアップロードしてください。"
    }
  }

  restoreInitial() {
    if (this.initialImageSrc) {
      this.imageTarget.src = this.initialImageSrc
      this.imageTarget.alt = "元画像"
      this.displayTarget.hidden = false
      this.element.dispatchEvent(new CustomEvent("source-image:changed", {
        bubbles: true,
        detail: { url: this.initialImageSrc }
      }))

      if (this.hasLabelTarget) {
        this.labelTarget.hidden = this.initialLabel.length === 0
        this.labelTarget.textContent = this.initialLabel
      }

      if (this.hasHintTarget) {
        this.hintTarget.textContent = this.initialHint
      }
      return
    }

    this.imageTarget.removeAttribute("src")
    this.imageTarget.alt = ""
    this.displayTarget.hidden = true
  }

  revokePreviewUrl() {
    if (!this.previewUrl) return

    URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = null
  }
}
