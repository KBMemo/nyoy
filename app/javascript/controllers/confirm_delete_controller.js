import { Controller } from "@hotwired/stimulus"

// Turbo's data-turbo-confirm is not always invoked for button_to delete forms
// in this app, so guard submission with a capture-phase confirm dialog.
export default class extends Controller {
  static values = {
    message: { type: String, default: "削除しますか？" }
  }

  connect() {
    this.onSubmit = (event) => {
      if (!window.confirm(this.messageValue)) {
        event.preventDefault()
        event.stopImmediatePropagation()
      }
    }

    this.element.addEventListener("submit", this.onSubmit, true)
  }

  disconnect() {
    this.element.removeEventListener("submit", this.onSubmit, true)
  }
}
