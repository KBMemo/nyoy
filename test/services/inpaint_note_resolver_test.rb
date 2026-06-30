# frozen_string_literal: true

require "test_helper"

class InpaintNoteResolverTest < ActiveSupport::TestCase
  test "returns blank result for empty note" do
    result = InpaintNoteResolver.call("")

    assert_nil result.original
    assert_nil result.english
    assert_not result.translated
  end

  test "passes through english note without translation" do
    translator = Class.new do
      def translate(*) = raise "should not translate"
    end.new

    result = InpaintNoteResolver.call("natural hands", translator: translator)

    assert_equal "natural hands", result.original
    assert_equal "natural hands", result.english
    assert_not result.translated
  end

  test "translates japanese note" do
    translator = Class.new do
      def translate(note)
        "natural hands" if note == "手を自然に"
      end
    end.new

    result = InpaintNoteResolver.call("手を自然に", translator: translator)

    assert_equal "手を自然に", result.original
    assert_equal "natural hands", result.english
    assert result.translated
  end

  test "uses pretranslated note when provided" do
    translator = Class.new do
      def translate(*) = raise "should not translate"
    end.new

    result = InpaintNoteResolver.call("手を自然に", translated: "natural hands", translator: translator)

    assert_equal "natural hands", result.english
    assert_not result.translated
  end
end
