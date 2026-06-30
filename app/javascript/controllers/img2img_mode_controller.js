import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel", "modeInput", "maskInput", "sketchCompositeInput", "submitStatus"]
  static values = {
    activeMode: { type: String, default: "img2img" }
  }

  connect() {
    this.showMode(this.activeModeValue)
  }

  selectMode(event) {
    event.preventDefault()
    const mode = event.currentTarget.dataset.mode
    if (!mode) return

    this.modeInputTarget.value = mode
    this.showMode(mode)
  }

  showMode(mode) {
    this.activeModeValue = mode

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.mode === mode
      tab.classList.toggle("nyoy-img2img-tab-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.mode !== mode
    })

    this.clearSubmitStatus()
  }

  beforeSubmit(event) {
    this.clearSubmitStatus()

    const mode = this.modeInputTarget.value
    if (mode === "img2img") return

    if (mode === "inpaint_upload") {
      const maskField = this.element.querySelector('input[type="file"][name="img2img_generation[mask_image]"]')
      if (!maskField?.files?.length) {
        event.preventDefault()
        event.stopPropagation()
        this.showSubmitError("マスク画像を選択してください")
      }
      return
    }

    if (mode === "sketch" || mode === "inpaint_sketch") {
      const sketchController = this.findSketchController(mode)
      const sketchError = sketchController?.validationError()
      if (sketchError) {
        event.preventDefault()
        event.stopPropagation()
        this.showSubmitError(sketchError.message)
        return
      }

      try {
        this.sketchCompositeInputTarget.value = sketchController.exportCompositeDataUrl()
        if (mode === "inpaint_sketch") {
          this.maskInputTarget.value = sketchController.exportMaskFromStrokesDataUrl()
        }
      } catch (_error) {
        event.preventDefault()
        event.stopPropagation()
        this.showSubmitError(mode === "inpaint_sketch" ? "スケッチまたはマスクの保存に失敗しました" : "スケッチの保存に失敗しました")
        return
      }
    }

    if (mode === "inpaint") {
      const maskController = this.findMaskController(mode)
      const maskError = maskController?.validationError()
      if (maskError) {
        event.preventDefault()
        event.stopPropagation()
        this.showSubmitError(maskError.message)
        return
      }

      try {
        this.maskInputTarget.value = maskController.exportMaskDataUrl()
      } catch (_error) {
        event.preventDefault()
        event.stopPropagation()
        this.showSubmitError("マスクの保存に失敗しました")
      }
    }
  }

  findMaskController(mode) {
    const panel = this.panelTargets.find((entry) => entry.dataset.mode === mode)
    if (!panel) return null

    const element = panel.querySelector('[data-controller~="inpaint-mask"]')
    if (!element) return null

    return this.application.getControllerForElementAndIdentifier(element, "inpaint-mask")
  }

  findSketchController(mode) {
    const panel = this.panelTargets.find((entry) => entry.dataset.mode === mode)
    if (!panel) return null

    const element = panel.querySelector('[data-controller~="img2img-sketch"]')
    if (!element) return null

    return this.application.getControllerForElementAndIdentifier(element, "img2img-sketch")
  }

  showSubmitError(message) {
    if (!this.hasSubmitStatusTarget) return

    this.submitStatusTarget.textContent = message
    this.submitStatusTarget.classList.add("kb-text-danger")
    this.submitStatusTarget.classList.remove("kb-text-muted")
    this.submitStatusTarget.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  clearSubmitStatus() {
    if (!this.hasSubmitStatusTarget) return

    this.submitStatusTarget.textContent = ""
    this.submitStatusTarget.classList.remove("kb-text-danger")
    this.submitStatusTarget.classList.add("kb-text-muted")
  }
}
