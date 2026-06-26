import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "presetSelect",
    "generationPresetId",
    "sdModel",
    "width",
    "height",
    "steps",
    "cfgScale",
    "samplerName",
    "vaeTiling",
    "promptSkillId",
    "negativePrompt",
    "lorasField",
    "loraRows",
    "loraCatalog"
  ]

  static values = {
    presets: Object,
    loras: Array,
    initialLoras: Array
  }

  connect() {
    this.initializeLoras()
  }

  initializeLoras() {
    let loras = this.parseLorasField()

    if (!loras.length && this.initialLorasValue.length) {
      loras = this.initialLorasValue
    }

    if (!loras.length && this.hasPresetSelectTarget && this.presetSelectTarget.value) {
      loras = this.presetLoras(this.presetSelectTarget.value)
    }

    if (loras.length) {
      this.renderLoras(loras)
    }
  }

  applyPreset() {
    const presetId = this.presetSelectTarget.value

    if (this.hasGenerationPresetIdTarget) {
      this.generationPresetIdTarget.value = presetId
    }

    if (!presetId) {
      this.renderLoras([])
      return
    }

    const preset = this.presetsValue[presetId]
    if (!preset) return

    this.sdModelTarget.value = preset.sd_model
    this.widthTarget.value = preset.width
    this.heightTarget.value = preset.height
    this.stepsTarget.value = preset.steps
    this.cfgScaleTarget.value = preset.cfg_scale
    this.samplerNameTarget.value = preset.sampler_name
    this.vaeTilingTarget.checked = preset.vae_tiling

    if (this.hasPromptSkillIdTarget) {
      this.promptSkillIdTarget.value = preset.prompt_skill_id || ""
    } else {
      const field = this.promptSkillField()
      if (field) field.value = preset.prompt_skill_id || ""
    }

    this.renderLoras(preset.loras || [])
  }

  addLora(event) {
    event.preventDefault()

    const selected = this.loraCatalogTarget.selectedOptions[0]
    if (!selected || !selected.value) return

    const loras = this.currentLoras()
    if (loras.some((entry) => entry.path === selected.value)) return

    loras.push({
      name: selected.dataset.name,
      path: selected.value,
      multiplier: 0.8
    })

    this.renderLoras(loras)
    this.loraCatalogTarget.value = ""
  }

  removeLora(event) {
    event.preventDefault()

    const index = Number(event.currentTarget.dataset.index)
    const loras = this.currentLoras()
    loras.splice(index, 1)
    this.renderLoras(loras)
  }

  updateLoraMultiplier() {
    this.syncLorasField()
  }

  renderLoras(loras) {
    this.loraRowsTarget.innerHTML = ""

    loras.forEach((entry, index) => {
      const row = document.createElement("div")
      row.className = "nyoy-lora-row"
      row.dataset.name = entry.name || ""
      row.dataset.path = entry.path || entry.name || ""
      row.innerHTML = `
        <span class="lora-name">${this.escapeHtml(entry.name || entry.path)}</span>
        <label>
          Weight
          <input type="number" min="0" max="2" step="0.05" value="${entry.multiplier ?? 0.8}"
            data-index="${index}" data-action="input->preset-form#updateLoraMultiplier">
        </label>
        <button type="button" class="kb-chrome-btn-secondary kb-btn-sm" data-index="${index}" data-action="preset-form#removeLora">削除</button>
      `
      this.loraRowsTarget.appendChild(row)
    })

    this.syncLorasField()
  }

  currentLoras() {
    return Array.from(this.loraRowsTarget.querySelectorAll(".nyoy-lora-row")).map((row) => ({
      name: row.dataset.name,
      path: row.dataset.path,
      multiplier: Number(row.querySelector('input[type="number"]')?.value || 0.8)
    }))
  }

  presetLoras(presetId) {
    return this.presetsValue[presetId]?.loras || []
  }

  parseLorasField() {
    if (!this.hasLorasFieldTarget) return []

    try {
      return JSON.parse(this.lorasFieldTarget.value || "[]")
    } catch {
      return []
    }
  }

  promptSkillField() {
    return this.element.closest("form")?.querySelector('[name$="[prompt_skill_id]"]')
  }

  syncLorasField() {
    this.lorasFieldTarget.value = JSON.stringify(this.currentLoras())
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
  }
}
