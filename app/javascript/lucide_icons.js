import { createIcons, Settings } from "lucide"

const LUCIDE_ICONS = {
  Settings
}

export function renderLucideIcons() {
  createIcons({ icons: LUCIDE_ICONS })
}

let lucideAfterStreamFrame = null

function scheduleLucideIconsAfterStream() {
  if (lucideAfterStreamFrame != null) cancelAnimationFrame(lucideAfterStreamFrame)
  lucideAfterStreamFrame = requestAnimationFrame(() => {
    lucideAfterStreamFrame = null
    renderLucideIcons()
  })
}

export function initLucideIcons() {
  document.addEventListener("turbo:load", renderLucideIcons)
  document.addEventListener("turbo:render", renderLucideIcons)

  document.addEventListener("turbo:before-stream-render", (event) => {
    const orig = event.detail?.render
    if (typeof orig !== "function") return

    event.detail.render = (streamElement) => {
      const result = orig(streamElement)
      Promise.resolve(result).finally(() => scheduleLucideIconsAfterStream())
      return result
    }
  })

  renderLucideIcons()
}
