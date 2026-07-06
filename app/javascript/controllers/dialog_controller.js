import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel"]

  open() {
    this.panelTarget.showModal()
  }

  close() {
    this.panelTarget.close()
  }

  backdropClose(event) {
    if (event.target === this.panelTarget) {
      this.close()
    }
  }
}
