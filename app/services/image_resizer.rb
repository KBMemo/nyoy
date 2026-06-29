# frozen_string_literal: true

require "image_processing/vips"
require "tempfile"

class ImageResizer
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
end
