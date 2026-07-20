import { Controller } from "@hotwired/stimulus"
import { renderLucideIcons } from "../lucide_icons"

const REFRESH_REGION_IDS = [
  "llama-server-refresh-state",
  "llama-server-reconciliation",
  "llama-server-inventory",
  "llama-server-connections",
  "llama-server-models",
  "llama-server-operations"
]

export default class extends Controller {
  static targets = ["serverQuery", "operationStatus", "refreshButton", "status"]
  static values = { url: String, interval: { type: Number, default: 4000 } }

  connect() {
    this.refreshing = false
    this.visibilityHandler = () => this.syncPolling()
    document.addEventListener("visibilitychange", this.visibilityHandler)
    this.applyFilters()
    this.syncPolling()
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.visibilityHandler)
    this.stopPolling()
  }

  filter() {
    this.applyFilters()
  }

  refresh() {
    this.load()
  }

  async load() {
    if (this.refreshing || document.hidden) return

    this.refreshing = true
    this.refreshButtonTarget.disabled = true
    try {
      const response = await fetch(this.urlValue, {
        headers: { Accept: "text/html" },
        credentials: "same-origin"
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      if (response.redirected) {
        window.Turbo.visit(response.url)
        return
      }

      const parsed = new DOMParser().parseFromString(await response.text(), "text/html")
      const topologyChanged = REFRESH_REGION_IDS.some((id) => {
        return Boolean(document.getElementById(id)) !== Boolean(parsed.getElementById(id))
      })
      if (topologyChanged) {
        window.Turbo.visit(this.urlValue)
        return
      }

      for (const id of REFRESH_REGION_IDS) {
        const current = document.getElementById(id)
        const replacement = parsed.getElementById(id)
        if (current && replacement) current.replaceWith(replacement)
      }
      this.statusTarget.textContent = `更新 ${new Intl.DateTimeFormat("ja-JP", { timeStyle: "medium" }).format(new Date())}`
      this.applyFilters()
      renderLucideIcons()
      this.syncPolling()
    } catch (_error) {
      this.statusTarget.textContent = "更新失敗"
    } finally {
      this.refreshing = false
      this.refreshButtonTarget.disabled = false
    }
  }

  syncPolling() {
    const active = document.getElementById("llama-server-refresh-state")?.dataset.active === "true"
    this.statusTarget.textContent = active ? "自動更新中" : this.statusTarget.textContent

    if (active && !document.hidden) {
      if (!this.timer) this.timer = window.setInterval(() => this.load(), this.intervalValue)
    } else {
      this.stopPolling()
    }
  }

  stopPolling() {
    if (!this.timer) return

    window.clearInterval(this.timer)
    this.timer = null
  }

  applyFilters() {
    const query = this.serverQueryTarget.value.trim().toLocaleLowerCase("ja")
    document.querySelectorAll("[data-llama-server-row]").forEach((row) => {
      row.hidden = query.length > 0 && !row.dataset.filterText.toLocaleLowerCase("ja").includes(query)
    })

    const status = this.operationStatusTarget.value
    document.querySelectorAll("[data-llama-operation-row]").forEach((row) => {
      row.hidden = status.length > 0 && row.dataset.status !== status
    })
  }
}
