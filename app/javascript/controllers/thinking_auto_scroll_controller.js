import { Controller } from "@hotwired/stimulus"

// Follow state is kept at module scope (not on the instance) so it survives the
// disconnect/reconnect that Turbo triggers on every streaming re-render. Bound
// the map so a long-lived session does not accumulate entries indefinitely.
const followByMessageId = new Map()
const MAX_TRACKED = 200

export default class extends Controller {
  connect() {
    const match = this.element.id.match(/^message_(\d+)_thinking$/)
    if (!match) return

    this.messageId = match[1]
    if (!followByMessageId.has(this.messageId)) {
      followByMessageId.set(this.messageId, true)
      this.pruneTrackedState()
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

  pruneTrackedState() {
    while (followByMessageId.size > MAX_TRACKED) {
      const oldest = followByMessageId.keys().next().value
      followByMessageId.delete(oldest)
    }
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
