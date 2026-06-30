import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "sourceImage",
    "viewport",
    "overlayCanvas",
    "strokeCanvas",
    "status",
    "brushSizeInput",
    "brushButton",
    "eraserButton"
  ]

  connect() {
    this.drawing = false
    this.mode = "brush"
    this.lastPoint = null
    this.brushSize = 24
    this.activePointerId = null
    this.hasStrokes = false

    this.boundSourceChanged = this.onSourceChanged.bind(this)
    this.element.addEventListener("source-image:changed", this.boundSourceChanged)

    const image = this.sourceImageTarget
    image.addEventListener("load", () => this.initialize())
    image.addEventListener("error", () => this.setStatus("画像を読み込めませんでした"))

    if (image.complete && image.naturalWidth > 0) {
      this.initialize()
    }

    this.updateToolUi()
  }

  disconnect() {
    this.element.removeEventListener("source-image:changed", this.boundSourceChanged)
    if (this.resizeOverlayBound) {
      window.removeEventListener("resize", this.resizeOverlayBound)
    }
  }

  onSourceChanged(event) {
    const url = event.detail?.url
    if (!url) return

    this.initialized = false
    this.hasStrokes = false
    this.sourceImageTarget.src = url
  }

  initialize() {
    this.naturalWidth = this.sourceImageTarget.naturalWidth
    this.naturalHeight = this.sourceImageTarget.naturalHeight
    if (this.naturalWidth <= 0 || this.naturalHeight <= 0) return

    const strokeCanvas = this.strokeCanvasTarget
    strokeCanvas.width = this.naturalWidth
    strokeCanvas.height = this.naturalHeight
    this.strokeCtx = strokeCanvas.getContext("2d", { willReadFrequently: true })
    this.resetStrokeCanvas()

    this.brushSize = parseInt(this.brushSizeInputTarget.value, 10) || 24
    this.resizeOverlay()

    if (!this.resizeOverlayBound) {
      this.resizeOverlayBound = () => this.resizeOverlay()
      window.addEventListener("resize", this.resizeOverlayBound)
    }

    this.initialized = true
    this.setStatus("スケッチを描いてください")
  }

  resetStrokeCanvas() {
    this.strokeCtx.clearRect(0, 0, this.naturalWidth, this.naturalHeight)
    this.hasStrokes = false
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
    ctx.clearRect(0, 0, this.displayWidth, this.displayHeight)
    ctx.drawImage(this.sourceImageTarget, 0, 0, this.displayWidth, this.displayHeight)
    ctx.drawImage(this.strokeCanvasTarget, 0, 0, this.displayWidth, this.displayHeight)
  }

  brushSizeChanged() {
    this.brushSize = parseInt(this.brushSizeInputTarget.value, 10) || 24
  }

  useBrush() {
    this.mode = "brush"
    this.updateToolUi()
    this.setStatus("ブラシ: スケッチを描く")
  }

  useEraser() {
    this.mode = "eraser"
    this.updateToolUi()
    this.setStatus("消しゴム: スケッチを消す")
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

  clearStrokes() {
    this.resetStrokeCanvas()
    this.redrawOverlay()
    this.setStatus("スケッチをクリアしました")
  }

  pointerDown(event) {
    if (!this.strokeCtx) return

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
    const ctx = this.strokeCtx
    ctx.save()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    ctx.lineWidth = this.brushSize

    if (this.mode === "eraser") {
      ctx.globalCompositeOperation = "destination-out"
      ctx.strokeStyle = "rgba(0,0,0,1)"
    } else {
      ctx.globalCompositeOperation = "source-over"
      ctx.strokeStyle = "rgba(255, 80, 80, 0.85)"
    }

    ctx.beginPath()
    ctx.moveTo(from.x, from.y)
    ctx.lineTo(to.x, to.y)
    ctx.stroke()
    ctx.restore()
    this.markStrokesDirty()
    this.redrawOverlay()
  }

  paintPoint(point) {
    const ctx = this.strokeCtx
    ctx.save()

    if (this.mode === "eraser") {
      ctx.globalCompositeOperation = "destination-out"
      ctx.fillStyle = "rgba(0,0,0,1)"
    } else {
      ctx.globalCompositeOperation = "source-over"
      ctx.fillStyle = "rgba(255, 80, 80, 0.85)"
    }

    ctx.beginPath()
    ctx.arc(point.x, point.y, this.brushSize / 2, 0, Math.PI * 2)
    ctx.fill()
    ctx.restore()
    this.markStrokesDirty()
    this.redrawOverlay()
  }

  markStrokesDirty() {
    this.hasStrokes = true
  }

  validationError() {
    if (!this.initialized || !this.strokeCtx) {
      return { message: "画像の読み込みが完了していません" }
    }

    if (!this.hasStrokes || !this.strokeHasContent()) {
      return { message: "スケッチを描いてください" }
    }

    return null
  }

  strokeHasContent() {
    const { data } = this.strokeCtx.getImageData(0, 0, this.naturalWidth, this.naturalHeight)
    for (let index = 3; index < data.length; index += 4) {
      if (data[index] > 0) return true
    }
    return false
  }

  exportCompositeDataUrl() {
    const exportCanvas = document.createElement("canvas")
    exportCanvas.width = this.naturalWidth
    exportCanvas.height = this.naturalHeight
    const exportCtx = exportCanvas.getContext("2d")
    exportCtx.drawImage(this.sourceImageTarget, 0, 0)
    exportCtx.drawImage(this.strokeCanvasTarget, 0, 0)
    return exportCanvas.toDataURL("image/png")
  }

  exportMaskFromStrokesDataUrl() {
    const strokeData = this.strokeCtx.getImageData(0, 0, this.naturalWidth, this.naturalHeight)
    const exportCanvas = document.createElement("canvas")
    exportCanvas.width = this.naturalWidth
    exportCanvas.height = this.naturalHeight
    const exportCtx = exportCanvas.getContext("2d")
    const maskData = exportCtx.createImageData(this.naturalWidth, this.naturalHeight)

    for (let index = 0; index < strokeData.data.length; index += 4) {
      const alpha = strokeData.data[index + 3]
      const value = alpha > 0 ? 255 : 0
      maskData.data[index] = value
      maskData.data[index + 1] = value
      maskData.data[index + 2] = value
      maskData.data[index + 3] = 255
    }

    exportCtx.putImageData(maskData, 0, 0)
    return exportCanvas.toDataURL("image/png")
  }

  setStatus(message, { danger = false } = {}) {
    if (!this.hasStatusTarget) return

    this.statusTarget.textContent = message
    this.statusTarget.classList.toggle("kb-text-danger", danger)
    this.statusTarget.classList.toggle("kb-text-muted", !danger)
  }
}
