import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "image", "caption", "meta", "download"]

  open(event) {
    event.preventDefault()
    event.stopPropagation()

    const button = event.currentTarget
    this.imageTarget.src = button.dataset.imagePreviewUrl
    this.imageTarget.alt = button.dataset.imagePreviewLabel || ""
    this.captionTarget.textContent = button.dataset.imagePreviewLabel || ""
    this.metaTarget.textContent = "読み込み中…"

    if (this.hasDownloadTarget) {
      this.downloadTarget.href = button.dataset.imagePreviewDownloadUrl || button.dataset.imagePreviewUrl
      this.downloadTarget.hidden = !button.dataset.imagePreviewDownloadUrl
    }

    this.imageTarget.onload = () => {
      const { naturalWidth, naturalHeight } = this.imageTarget
      this.metaTarget.textContent = `${naturalWidth}×${naturalHeight}px`
    }
    this.imageTarget.onerror = () => {
      this.metaTarget.textContent = "画像を読み込めませんでした"
    }

    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
    this.imageTarget.removeAttribute("src")
  }

  backdropClose(event) {
    if (event.target === this.dialogTarget) {
      this.close()
    }
  }
}
