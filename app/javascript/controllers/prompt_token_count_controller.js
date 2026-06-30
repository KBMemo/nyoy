import { Controller } from "@hotwired/stimulus"

const CLIP_TOKEN_LIMIT = 75

export default class extends Controller {
  static targets = ["badge", "field"]
  static values = {
    countUrl: String
  }

  connect() {
    this.debounceTimer = null

    if (this.hasFieldTarget) {
      this.boundUpdate = () => this.scheduleUpdate()
      this.fieldTarget.addEventListener("input", this.boundUpdate)
      if (this.fieldTarget.value.trim()) {
        this.scheduleUpdate()
      }
    }
  }

  disconnect() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    if (this.hasFieldTarget && this.boundUpdate) {
      this.fieldTarget.removeEventListener("input", this.boundUpdate)
    }
  }

  update() {
    this.scheduleUpdate()
  }

  scheduleUpdate() {
    if (this.debounceTimer) {
      clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = setTimeout(() => {
      this.debounceTimer = null
      this.updateBadge()
    }, 150)
  }

  async updateBadge() {
    if (!this.hasBadgeTarget) return

    const text = this.hasFieldTarget ? this.fieldTarget.value : ""
    if (!text.trim()) {
      this.renderBadge(0)
      return
    }

    try {
      const data = await this.fetchCount(text)
      this.renderBadge(data.count, data.over_limit)
    } catch (_error) {
      // Keep the server-rendered badge when recounting fails.
    }
  }

  async fetchCount(text) {
    const response = await fetch(this.countUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ text })
    })

    if (!response.ok) {
      throw new Error("token count failed")
    }

    return response.json()
  }

  renderBadge(count, overLimit = count > CLIP_TOKEN_LIMIT) {
    this.badgeTarget.textContent = `${count} / ${CLIP_TOKEN_LIMIT}`
    this.badgeTarget.classList.toggle("nyoy-prompt-token-count-over", overLimit)
    this.badgeTarget.classList.toggle("kb-text-muted", !overLimit)
    this.badgeTarget.classList.toggle("kb-text-danger", overLimit)
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content || ""
  }
}
