# -*- encoding: utf-8 -*-

require 'test_helper'
require 'stringio'
require 'hexapdf/font/true_type'

describe HexaPDF::Font::TrueType::Subsetter do
  before do
    font_file = File.join(TEST_DATA_DIR, "fonts", "Ubuntu-Title.ttf")
    @font = HexaPDF::Font::TrueType::Font.new(File.open(font_file))
    @subsetter = HexaPDF::Font::TrueType::Subsetter.new(@font)
  end

  after do
    @font.io.close
  end

  it "adds glyphs to the subset" do
    assert_equal(1, @subsetter.use_glyph(5))
    assert_equal(2, @subsetter.use_glyph(6))
    assert_equal(1, @subsetter.use_glyph(5))
  end

  it "creates the subset font file" do
    gid = @font[:cmap].preferred_table[0x41]
    @subsetter.use_glyph(gid)
    subset = HexaPDF::Font::TrueType::Font.new(StringIO.new(@subsetter.build_font))

    assert(subset[:head])
    assert(subset[:head].checksum_valid?)
    assert(subset[:hhea])
    assert(subset[:hhea].checksum_valid?)
    assert(subset[:glyf])
    assert(subset[:glyf].checksum_valid?)
    assert(subset[:loca])
    assert(subset[:loca].checksum_valid?)
    assert(subset[:maxp])
    assert(subset[:maxp].checksum_valid?)
    assert(subset[:hmtx])
    assert(subset[:hmtx].checksum_valid?)

    assert(Time.now - subset[:head].modified < 10)
    assert_equal(2, subset[:maxp].num_glyphs)
    assert_equal(2, subset[:hhea].num_of_long_hor_metrics)
    assert_equal(3, subset[:loca].offsets.length)

    assert_equal(subset[:hmtx][0], @font[:hmtx][0])
    assert_equal(subset[:hmtx][1], @font[:hmtx][gid])

    assert_equal(subset[:glyf][1].raw_data, @font[:glyf][gid].raw_data)
  end

  it "correctly subsets compound glyphs" do
    font_file = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
    skip unless File.exist?(font_file)

    begin
      @font = HexaPDF::Font::TrueType::Font.new(File.open(font_file))
      @subsetter = HexaPDF::Font::TrueType::Subsetter.new(@font)

      @subsetter.use_glyph(@font[:cmap].preferred_table['À'.ord])
      subset = HexaPDF::Font::TrueType::Font.new(StringIO.new(@subsetter.build_font))

      assert_equal(4, subset[:maxp].num_glyphs)
      assert_equal([2, 3], subset[:glyf][1].components)
    ensure
      @font.io.close
    end
  end
end
