import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "presetSelect",
    "refinePresetId",
    "refineSteps",
    "refineDenoisingStrength",
    "enableHires",
    "hiresUpscaler",
    "hiresScale",
    "hiresSteps",
    "hiresDenoisingStrength"
  ]

  static values = {
    presets: Object
  }

  applyPreset() {
    const presetId = this.presetSelectTarget.value

    if (this.hasRefinePresetIdTarget) {
      this.refinePresetIdTarget.value = presetId
    }

    if (!presetId) return

    const preset = this.presetsValue[presetId]
    if (!preset) return

    if (this.hasRefineStepsTarget) {
      this.refineStepsTarget.value = preset.refine_steps ?? ""
    }
    if (this.hasRefineDenoisingStrengthTarget) {
      this.refineDenoisingStrengthTarget.value = preset.refine_denoising_strength
    }
    if (this.hasEnableHiresTarget) {
      this.enableHiresTarget.checked = preset.enable_hires
    }
    if (this.hasHiresUpscalerTarget) {
      this.hiresUpscalerTarget.value = preset.hires_upscaler
    }
    if (this.hasHiresScaleTarget) {
      this.hiresScaleTarget.value = preset.hires_scale
    }
    if (this.hasHiresStepsTarget) {
      this.hiresStepsTarget.value = preset.hires_steps ?? ""
    }
    if (this.hasHiresDenoisingStrengthTarget) {
      this.hiresDenoisingStrengthTarget.value = preset.hires_denoising_strength
    }
  }
}
