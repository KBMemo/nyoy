# frozen_string_literal: true

require "image_processing/vips"
require "tempfile"

class ImageResizer
  VISION_MAX_EDGE = 1024

  def self.resize_png(png_data, width:, height:)
    Tempfile.create(["resize", ".png"]) do |file|
      file.binmode
      file.write(png_data)
      file.rewind

      ImageProcessing::Vips
        .source(file.path)
        .resize_to_fill(width, height)
        .call
        .read
    end
  end

  def self.resize_to_limit(image_data, max_edge: VISION_MAX_EDGE, mime_type: "image/png")
    image = Vips::Image.new_from_buffer(image_data, "")
    return [image_data, mime_type] if [image.width, image.height].max <= max_edge

    Tempfile.create(["resize", ".img"]) do |file|
      file.binmode
      file.write(image_data)
      file.rewind

      resized = ImageProcessing::Vips
        .source(file.path)
        .resize_to_limit(max_edge, max_edge)
        .convert("png")
        .call
        .read

      [resized, "image/png"]
    end
  end
end
