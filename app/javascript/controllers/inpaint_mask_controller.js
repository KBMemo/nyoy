import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "sourceImage",
    "viewport",
    "overlayCanvas",
    "maskCanvas",
    "maskInput",
    "brushSizeInput",
    "status",
    "submitStatus",
    "submitButton",
    "brushButton",
    "eraserButton"
  ]

  static values = {
    imageUrl: String,
    submitLabel: { type: String, default: "部分修正を実行" },
    submittingLabel: { type: String, default: "送信中…" }
  }

  connect() {
    this.drawing = false
    this.mode = "brush"
    this.lastPoint = null
    this.brushSize = 32
    this.activePointerId = null
    this.onTurboSubmitEnd = this.onTurboSubmitEnd.bind(this)

    const image = this.sourceImageTarget
    image.addEventListener("load", () => this.initialize())
    image.addEventListener("error", () => this.setStatus("画像を読み込めませんでした"))

    if (!image.getAttribute("src") && this.imageUrlValue) {
      image.src = this.imageUrlValue
    }

    if (image.complete && image.naturalWidth > 0) {
      this.initialize()
    }

    this.element.addEventListener("turbo:submit-end", this.onTurboSubmitEnd)
    this.updateToolUi()
  }

  disconnect() {
    this.initialized = false
    this.element.removeEventListener("turbo:submit-end", this.onTurboSubmitEnd)
    if (this.resizeOverlayBound) {
      window.removeEventListener("resize", this.resizeOverlayBound)
    }
  }

  initialize() {
    if (this.initialized) return

    this.naturalWidth = this.sourceImageTarget.naturalWidth
    this.naturalHeight = this.sourceImageTarget.naturalHeight
    if (this.naturalWidth <= 0 || this.naturalHeight <= 0) return

    this.initialized = true

    const maskCanvas = this.maskCanvasTarget
    maskCanvas.width = this.naturalWidth
    maskCanvas.height = this.naturalHeight
    this.maskCtx = maskCanvas.getContext("2d", { willReadFrequently: true })
    this.resetMaskCanvas()

    this.brushSize = parseInt(this.brushSizeInputTarget.value, 10) || 32
    this.resizeOverlay()
    this.resizeOverlayBound = () => this.resizeOverlay()
    window.addEventListener("resize", this.resizeOverlayBound)
    this.setStatus("修正したい範囲を塗ってください")
  }

  resetMaskCanvas() {
    this.maskCtx.clearRect(0, 0, this.naturalWidth, this.naturalHeight)
    this.hasMaskStrokes = false
  }

  resizeOverlay() {
    const viewport = this.viewportTarget
    const maxWidth = viewport.clientWidth || this.naturalWidth
    const scale = Math.min(1, maxWidth / this.naturalWidth)
    this.displayScale = scale
    this.displayWidth = Math.round(this.naturalWidth * scale)
    this.displayHeight = Math.round(this.naturalHeight * scale)

    const canvas = this.overlayCanvasTarget
    canvas.width = this.displayWidth
    canvas.height = this.displayHeight
    canvas.style.width = `${this.displayWidth}px`
    canvas.style.height = `${this.displayHeight}px`
    this.overlayCtx = canvas.getContext("2d")
    this.redrawOverlay()
  }

  redrawOverlay() {
    if (!this.overlayCtx) return

    const ctx = this.overlayCtx
    const width = this.displayWidth
    const height = this.displayHeight

    ctx.clearRect(0, 0, width, height)
    ctx.drawImage(this.sourceImageTarget, 0, 0, width, height)
    this.paintMaskHighlight(ctx, width, height)
  }

  paintMaskHighlight(ctx, width, height) {
    if (!this.maskCtx) return

    const maskData = this.maskCtx.getImageData(0, 0, this.naturalWidth, this.naturalHeight)
    const scaleX = this.naturalWidth / width
    const scaleY = this.naturalHeight / height
    const overlay = ctx.createImageData(width, height)

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const maskX = Math.min(this.naturalWidth - 1, Math.floor(x * scaleX))
        const maskY = Math.min(this.naturalHeight - 1, Math.floor(y * scaleY))
        const maskAlpha = maskData.data[(maskY * this.naturalWidth + maskX) * 4 + 3]
        if (maskAlpha === 0) continue

        const index = (y * width + x) * 4
        overlay.data[index] = 255
        overlay.data[index + 1] = 80
        overlay.data[index + 2] = 80
        overlay.data[index + 3] = Math.round(115 * (maskAlpha / 255))
      }
    }

    const highlight = document.createElement("canvas")
    highlight.width = width
    highlight.height = height
    highlight.getContext("2d").putImageData(overlay, 0, 0)
    ctx.drawImage(highlight, 0, 0)
  }

  brushSizeChanged() {
    this.brushSize = parseInt(this.brushSizeInputTarget.value, 10) || 32
  }

  useBrush() {
    this.mode = "brush"
    this.updateToolUi()
    this.setStatus("ブラシ: 修正したい範囲を塗る")
  }

  useEraser() {
    this.mode = "eraser"
    this.updateToolUi()
    this.setStatus("消しゴム: マスクを消す")
  }

  updateToolUi() {
    const brushActive = this.mode === "brush"

    if (this.hasBrushButtonTarget) {
      this.brushButtonTarget.classList.toggle("nyoy-inpaint-tool-active", brushActive)
      this.brushButtonTarget.setAttribute("aria-pressed", brushActive ? "true" : "false")
    }

    if (this.hasEraserButtonTarget) {
      this.eraserButtonTarget.classList.toggle("nyoy-inpaint-tool-active", !brushActive)
      this.eraserButtonTarget.setAttribute("aria-pressed", brushActive ? "false" : "true")
    }
  }

  clearMask() {
    this.resetMaskCanvas()
    this.redrawOverlay()
    this.setStatus("マスクをクリアしました")
  }

  pointerDown(event) {
    if (!this.maskCtx) return

    event.preventDefault()
    this.drawing = true
    this.activePointerId = event.pointerId
    this.overlayCanvasTarget.setPointerCapture(event.pointerId)
    this.lastPoint = this.pointerPosition(event)
    this.paintPoint(this.lastPoint)
  }

  pointerMove(event) {
    if (!this.drawing || event.pointerId !== this.activePointerId) return

    event.preventDefault()
    const point = this.pointerPosition(event)
    this.paintStroke(this.lastPoint, point)
    this.lastPoint = point
  }

  pointerUp(event) {
    if (!this.drawing || event.pointerId !== this.activePointerId) return

    event.preventDefault()
    this.drawing = false
    this.activePointerId = null
    this.lastPoint = null
    if (this.overlayCanvasTarget.hasPointerCapture(event.pointerId)) {
      this.overlayCanvasTarget.releasePointerCapture(event.pointerId)
    }
  }

  validateClick(event) {
    const error = this.validationError()
    if (!error) return

    event.preventDefault()
    event.stopImmediatePropagation()
    this.showValidationError(error)
  }

  beforeSubmit(event) {
    const error = this.validationError()
    if (error) {
      event.preventDefault()
      event.stopPropagation()
      this.queueSubmitButtonReset(event.submitter)
      this.showValidationError(error)
      return
    }

    try {
      this.maskInputTarget.value = this.exportMaskDataUrl()
      this.setSubmitStatus("")
      this.setSubmitLoading(event.submitter)
    } catch (_error) {
      event.preventDefault()
      event.stopPropagation()
      this.queueSubmitButtonReset(event.submitter)
      this.showValidationError({ kind: "mask", message: "マスクの保存に失敗しました" })
    }
  }

  validationError() {
    if (!this.initialized || !this.maskCtx) {
      return { kind: "mask", message: "画像の読み込みが完了していません" }
    }

    if (!this.hasMaskStrokes || !this.maskHasContent()) {
      return { kind: "mask", message: "修正したい範囲をマスクしてください" }
    }

    const delta = this.element.querySelector('[name="inpaint_prompt_delta"]')?.value.trim()
    const note = this.element.querySelector('[name="inpaint_note"]')?.value.trim()
    if (!delta && !note) {
      return { kind: "prompt", message: "修正指示または差分プロンプトを入力してください" }
    }

    return null
  }

  showValidationError(error) {
    if (error.kind === "prompt") {
      this.setSubmitStatus(error.message)
      return
    }

    this.setStatus(error.message, { danger: true })
    this.scrollStatusIntoView()
  }

  setSubmitLoading(button) {
    const submitter = button || this.submitButtonTarget
    if (!submitter) return

    submitter.disabled = true
    submitter.value = this.submittingLabelValue
  }

  queueSubmitButtonReset(button) {
    const reset = () => this.resetSubmitButton(button)
    requestAnimationFrame(() => {
      reset()
      setTimeout(reset, 0)
    })
  }

  resetSubmitButton(button) {
    const submitter = button || (this.hasSubmitButtonTarget ? this.submitButtonTarget : null)
    if (!submitter) return

    submitter.disabled = false
    submitter.value = this.submitLabelValue
  }

  onTurboSubmitEnd() {
    this.resetSubmitButton()
  }

  scrollStatusIntoView() {
    this.statusTarget?.scrollIntoView({ behavior: "smooth", block: "center" })
  }

  markMaskDirty() {
    this.hasMaskStrokes = true
  }

  pointerPosition(event) {
    const rect = this.overlayCanvasTarget.getBoundingClientRect()
    if (rect.width <= 0 || rect.height <= 0) {
      return { x: 0, y: 0 }
    }

    const x = ((event.clientX - rect.left) / rect.width) * this.naturalWidth
    const y = ((event.clientY - rect.top) / rect.height) * this.naturalHeight
    return { x, y }
  }

  paintStroke(from, to) {
    const ctx = this.maskCtx
    ctx.save()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    ctx.lineWidth = this.brushSize

    if (this.mode === "eraser") {
      ctx.globalCompositeOperation = "destination-out"
      ctx.strokeStyle = "rgba(0,0,0,1)"
    } else {
      ctx.globalCompositeOperation = "source-over"
      ctx.strokeStyle = "#ffffff"
    }

    ctx.beginPath()
    ctx.moveTo(from.x, from.y)
    ctx.lineTo(to.x, to.y)
    ctx.stroke()
    ctx.restore()
    this.markMaskDirty()
    this.redrawOverlay()
  }

  paintPoint(point) {
    const ctx = this.maskCtx
    ctx.save()

    if (this.mode === "eraser") {
      ctx.globalCompositeOperation = "destination-out"
      ctx.fillStyle = "rgba(0,0,0,1)"
    } else {
      ctx.globalCompositeOperation = "source-over"
      ctx.fillStyle = "#ffffff"
    }

    ctx.beginPath()
    ctx.arc(point.x, point.y, this.brushSize / 2, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()
    this.markMaskDirty()
    this.redrawOverlay()
  }

  exportMaskDataUrl() {
    const exportCanvas = document.createElement("canvas")
    exportCanvas.width = this.naturalWidth
    exportCanvas.height = this.naturalHeight
    const exportCtx = exportCanvas.getContext("2d")
    exportCtx.fillStyle = "#000000"
    exportCtx.fillRect(0, 0, this.naturalWidth, this.naturalHeight)
    exportCtx.drawImage(this.maskCanvasTarget, 0, 0)
    return exportCanvas.toDataURL("image/png")
  }

  setStatus(message, { danger = false } = {}) {
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = message
      this.statusTarget.classList.toggle("kb-text-danger", danger)
      this.statusTarget.classList.toggle("kb-text-muted", !danger)
    }
  }

  setSubmitStatus(message) {
    if (!this.hasSubmitStatusTarget) return

    this.submitStatusTarget.textContent = message
    this.submitStatusTarget.classList.toggle("kb-text-danger", message.length > 0)
    this.submitStatusTarget.classList.toggle("kb-text-muted", message.length === 0)
    if (message.length > 0) {
      this.submitStatusTarget.scrollIntoView({ behavior: "smooth", block: "center" })
    }
  }

  maskHasContent() {
    const { data } = this.maskCtx.getImageData(0, 0, this.naturalWidth, this.naturalHeight)
    for (let index = 3; index < data.length; index += 4) {
      if (data[index] > 0) return true
    }
    return false
  }
}
