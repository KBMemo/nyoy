import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tab", "panel", "submitButton"]
  static values = {
    activeSection: { type: String, default: "draft" },
    draftSubmitDisabled: { type: Boolean, default: false }
  }

  connect() {
    this.showSection(this.activeSectionValue)
  }

  selectSection(event) {
    event.preventDefault()
    const section = event.currentTarget.dataset.section
    if (!section) return

    this.showSection(section)
  }

  showSection(section) {
    this.activeSectionValue = section

    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.section === section
      tab.classList.toggle("nyoy-img2img-tab-active", active)
      tab.setAttribute("aria-selected", active ? "true" : "false")
    })

    this.panelTargets.forEach((panel) => {
      const active = panel.dataset.section === section
      panel.hidden = !active
      panel.querySelectorAll("input, select, textarea, button").forEach((field) => {
        if (field.type === "hidden") return
        if (field === this.submitButtonTarget) return
        field.disabled = !active
      })
    })

    const sharedFields = this.element.querySelectorAll("[data-image-generation-flow-shared]")
    sharedFields.forEach((field) => {
      field.disabled = false
    })

    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.value = section === "direct" ? "生成する" : "ラフを生成"
      this.submitButtonTarget.disabled = section === "draft" && this.draftSubmitDisabledValue
    }

    const sectionInput = this.element.querySelector('input[name="section"]')
    if (sectionInput) sectionInput.value = section
  }
}
