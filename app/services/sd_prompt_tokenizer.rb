# frozen_string_literal: true

require "zlib"
require "cgi"

class SdPromptTokenizer
  CLIP_TOKEN_LIMIT = 75

  class Error < StandardError; end

  TOKEN_PATTERN = /
    <\|startoftext\|> |
    <\|endoftext\|> |
    's | 't | 're | 've | 'm | 'll | 'd |
    [\p{L}\p{N}]+ |
    [^\s\p{L}\p{N}]+
  /ix

  class << self
    def count(text)
      encode(text).length
    end

    def encode(text)
      return [] if text.blank?

      tokenizer.encode(text)
    end

    def over_limit?(text)
      count(text) > CLIP_TOKEN_LIMIT
    end

    def label(text)
      count = count(text)
      "#{count} / #{CLIP_TOKEN_LIMIT}"
    end

    private

    def tokenizer
      @tokenizer ||= new
    end
  end

  def initialize(bpe_path: default_bpe_path)
    @byte_encoder = build_bytes_to_unicode
    @byte_decoder = @byte_encoder.invert
    load_bpe(bpe_path)
    @cache = {
      "<|startoftext|>" => "<|startoftext|>",
      "<|endoftext|>" => "<|endoftext|>"
    }
  end

  def encode(text)
    bpe_tokens = []
    clean_text(text).scan(TOKEN_PATTERN).each do |token|
      next if token.blank?

      piece = token.each_byte.map { |byte| @byte_encoder[byte] }.join
      bpe(piece).split.each do |bpe_token|
        bpe_tokens << @encoder.fetch(bpe_token)
      end
    end
    bpe_tokens
  end

  private

  def default_bpe_path
    Rails.root.join("vendor/clip/bpe_simple_vocab_16e6.txt.gz")
  end

  def clean_text(text)
    cleaned = CGI.unescapeHTML(text.to_s)
    cleaned.gsub(/\s+/, " ").strip.downcase
  end

  def load_bpe(path)
    raise Error, "missing CLIP BPE vocab: #{path}" unless File.exist?(path)

    merges = Zlib::GzipReader.open(path) { |gz| gz.read }.split("\n")
    merges = merges[1, 49_152 - 256 - 2]
    merges = merges.map { |line| line.split }

    vocab = @byte_encoder.values
    vocab += vocab.map { |token| "#{token}</w>" }
    merges.each { |first, second| vocab << "#{first}#{second}" }
    vocab << "<|startoftext|>" << "<|endoftext|>"

    @encoder = vocab.each_with_index.to_h
    @bpe_ranks = merges.each_with_index.to_h
  end

  def bpe(token)
    return @cache[token] if @cache.key?(token)

    if token.empty?
      @cache[token] = token
      return token
    end

    word = token[0..-2].chars + ["#{token[-1]}</w>"]
    pairs = pairs_for(word)
    return @cache[token] = word.join if pairs.empty?

    while pairs.any?
      bigram = pairs.min_by { |pair| @bpe_ranks.fetch(pair, Float::INFINITY) }
      break unless @bpe_ranks.key?(bigram)

      first, second = bigram
      new_word = []
      index = 0
      while index < word.length
        found = (index...word.length).find { |i| word[i] == first }
        unless found
          new_word.concat(word[index..])
          break
        end

        new_word.concat(word[index...found])
        index = found

        if word[index] == first && index < word.length - 1 && word[index + 1] == second
          new_word << "#{first}#{second}"
          index += 2
        else
          new_word << word[index]
          index += 1
        end
      end

      word = new_word
      break if word.length == 1

      pairs = pairs_for(word)
    end

    @cache[token] = word.join(" ")
    @cache[token]
  end

  def pairs_for(word)
    return [] if word.length < 2

    word.each_cons(2).to_a
  end

  def build_bytes_to_unicode
    bytes = (
      (33..126).to_a +
      (161..172).to_a +
      (174..255).to_a
    )
    chars = bytes.map { |byte| byte.chr(Encoding::UTF_8) }
    n = 0
    (0..255).each do |byte|
      next if bytes.include?(byte)

      bytes << byte
      chars << (n + 256).chr(Encoding::UTF_8)
      n += 1
    end
    bytes.zip(chars).to_h
  end
end
