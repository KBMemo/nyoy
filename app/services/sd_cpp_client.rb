# frozen_string_literal: true

require "base64"
require "net/http"
require "json"
require "uri"

class SdCppClient
  class Error < StandardError; end

  def initialize(base_url: NyoyConnectionStore.url(:sd_cpp))
    @base_url = base_url.sub(%r{/\z}, "")
  end

  def get_json(path)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Get.new(uri)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 30

    res = http.request(req)
    body = res.body.to_s
    json = JSON.parse(body)

    unless res.is_a?(Net::HTTPSuccess)
      raise Error, json["error"] || body
    end

    json
  rescue JSON::ParserError
    raise Error, body.presence || "invalid response from sd-server"
  end

  def txt2img(
    prompt:,
    negative_prompt: "",
    width: 512,
    height: 512,
    steps: 20,
    cfg_scale: 7.0,
    seed: -1,
    sampler_name: nil,
    vae_tiling: nil,
    lora: [],
    batch_size: 1,
    enable_hr: nil,
    hr_upscaler: nil,
    hr_scale: nil,
    hr_steps: nil,
    hr_denoising_strength: nil
  )
    images = txt2img_all(
      prompt: prompt,
      negative_prompt: negative_prompt,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      lora: lora,
      batch_size: batch_size,
      enable_hr: enable_hr,
      hr_upscaler: hr_upscaler,
      hr_scale: hr_scale,
      hr_steps: hr_steps,
      hr_denoising_strength: hr_denoising_strength
    )

    batch_size > 1 ? images : images.first
  end

  def txt2img_all(
    prompt:,
    negative_prompt: "",
    width: 512,
    height: 512,
    steps: 20,
    cfg_scale: 7.0,
    seed: -1,
    sampler_name: nil,
    vae_tiling: nil,
    lora: [],
    batch_size: 1,
    enable_hr: nil,
    hr_upscaler: nil,
    hr_scale: nil,
    hr_steps: nil,
    hr_denoising_strength: nil
  )
    payload = build_generation_payload(
      prompt: prompt,
      negative_prompt: negative_prompt,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      lora: lora
    )
    payload[:batch_size] = batch_size if batch_size > 1
    merge_hires_payload!(
      payload,
      enable_hr: enable_hr,
      hr_upscaler: hr_upscaler,
      hr_scale: hr_scale,
      hr_steps: hr_steps,
      hr_denoising_strength: hr_denoising_strength
    )

    decode_images(post_json("/sdapi/v1/txt2img", payload))
  end

  def img2img(
    prompt:,
    init_image:,
    negative_prompt: "",
    width: 512,
    height: 512,
    steps: 20,
    cfg_scale: 7.0,
    seed: -1,
    sampler_name: nil,
    vae_tiling: nil,
    denoising_strength: 0.4,
    lora: [],
    enable_hr: nil,
    hr_upscaler: nil,
    hr_scale: nil,
    hr_steps: nil,
    hr_denoising_strength: nil,
    hr_resize_x: nil,
    hr_resize_y: nil
  )
    payload = build_generation_payload(
      prompt: prompt,
      negative_prompt: negative_prompt,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      lora: lora
    )
    payload[:init_images] = [Base64.strict_encode64(init_image)]
    payload[:denoising_strength] = denoising_strength
    merge_hires_payload!(
      payload,
      enable_hr: enable_hr,
      hr_upscaler: hr_upscaler,
      hr_scale: hr_scale,
      hr_steps: hr_steps,
      hr_denoising_strength: hr_denoising_strength,
      hr_resize_x: hr_resize_x,
      hr_resize_y: hr_resize_y
    )

    decode_images(post_json("/sdapi/v1/img2img", payload)).first
  end

  def inpaint(
    prompt:,
    init_image:,
    mask:,
    negative_prompt: "",
    width: 512,
    height: 512,
    steps: 20,
    cfg_scale: 7.0,
    seed: -1,
    sampler_name: nil,
    vae_tiling: nil,
    denoising_strength: 0.55,
    lora: []
  )
    payload = build_generation_payload(
      prompt: prompt,
      negative_prompt: negative_prompt,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed,
      sampler_name: sampler_name,
      vae_tiling: vae_tiling,
      lora: lora
    )
    payload[:init_images] = [Base64.strict_encode64(init_image)]
    payload[:mask] = Base64.strict_encode64(mask)
    payload[:denoising_strength] = denoising_strength

    decode_images(post_json("/sdapi/v1/img2img", payload)).first
  end

  private

  def build_generation_payload(
    prompt:,
    negative_prompt:,
    width:,
    height:,
    steps:,
    cfg_scale:,
    seed:,
    sampler_name:,
    vae_tiling:,
    lora:
  )
    payload = {
      prompt: prompt,
      negative_prompt: negative_prompt,
      width: width,
      height: height,
      steps: steps,
      cfg_scale: cfg_scale,
      seed: seed
    }
    payload[:sampler_name] = sampler_name if sampler_name.present?
    payload[:vae_tiling] = vae_tiling unless vae_tiling.nil?
    payload[:loras] = lora if lora.present?
    payload
  end

  def merge_hires_payload!(payload, enable_hr:, hr_upscaler:, hr_scale:, hr_steps:, hr_denoising_strength:, hr_resize_x: nil, hr_resize_y: nil)
    return unless enable_hr

    payload[:enable_hr] = true
    payload[:hr_upscaler] = hr_upscaler if hr_upscaler.present?
    payload[:hr_scale] = hr_scale if hr_scale
    payload[:hr_steps] = hr_steps if hr_steps
    payload[:hr_resize_x] = hr_resize_x if hr_resize_x
    payload[:hr_resize_y] = hr_resize_y if hr_resize_y
    payload[:denoising_strength] = hr_denoising_strength if hr_denoising_strength && !payload.key?(:denoising_strength)
  end

  def decode_images(json)
    images = json.fetch("images", []).map { |image_b64| Base64.decode64(image_b64) }
    raise Error, "no image returned" if images.empty?

    images
  end

  def post_json(path, payload)
    uri = URI("#{@base_url}#{path}")
    req = Net::HTTP::Post.new(uri)
    req["Content-Type"] = "application/json"
    req.body = JSON.generate(payload)

    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5
    http.read_timeout = 600

    res = http.request(req)
    body = res.body.to_s

    json = JSON.parse(body)
    unless res.is_a?(Net::HTTPSuccess)
      raise Error, json["error"] || body
    end

    json
  rescue JSON::ParserError
    raise Error, body.presence || "invalid response from sd-server"
  end
end
