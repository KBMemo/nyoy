import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submitOnShortcut(event) {
    if (!(event.target instanceof HTMLTextAreaElement)) return
    if (event.key !== "Enter") return
    if (!event.ctrlKey && !event.metaKey) return
    if (event.isComposing) return

    event.preventDefault()
    this.element.requestSubmit()
  }
}
