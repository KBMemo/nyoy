import { Controller } from "@hotwired/stimulus"

const followByMessageId = new Map()

export default class extends Controller {
  connect() {
    const match = this.element.id.match(/^message_(\d+)_thinking$/)
    if (!match) return

    this.messageId = match[1]
    if (!followByMessageId.has(this.messageId)) {
      followByMessageId.set(this.messageId, true)
    }

    this.boundScroll = this.updateFollowState.bind(this)
    this.element.addEventListener("scroll", this.boundScroll, { passive: true })

    this.observer = new MutationObserver(() => this.scrollIfFollowing())
    this.observer.observe(this.element, {
      childList: true,
      characterData: true,
      subtree: true
    })

    this.scrollIfFollowing()
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.boundScroll)
    this.observer?.disconnect()
  }

  updateFollowState() {
    followByMessageId.set(this.messageId, this.atBottom())
  }

  scrollIfFollowing() {
    if (!followByMessageId.get(this.messageId)) return

    this.element.scrollTop = this.element.scrollHeight
  }

  atBottom() {
    const threshold = 24

    return this.element.scrollHeight - this.element.scrollTop - this.element.clientHeight <= threshold
  }
}
