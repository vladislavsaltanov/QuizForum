require "test_helper"

# The polish pass is pure CSS, so no request renders it. These assertions read
# the stylesheet off disk and pin the rules a regression would silently drop:
# the UA underline on button-shaped links, the divider between the question-page
# columns, and the urgency badge colours.
class UiPolishTest < ActionDispatch::IntegrationTest
  STYLE_SHEET = "app/assets/stylesheets/application.css"
  BUTTON_CHIPS = %w[.qf-ghost .qf-tab .qf-chip].freeze
  DIVIDER = ".qf-main-wide .qf-pane + .qf-pane::before"
  URGENT_CHIP = ".qf-chip.qf-chip-urgent"
  MIN_CONTRAST = 4.5

  test "button-shaped links and chips opt out of the UA underline in one shared rule" do
    rule = rules.find do |candidate|
      candidate[:declarations].match?(/text-decoration:\s*none/) &&
        (BUTTON_CHIPS - candidate[:selectors]).empty?
    end

    assert_not_nil rule,
      "#{STYLE_SHEET} must declare text-decoration: none for #{BUTTON_CHIPS.join(", ")} in one rule"
    assert_equal BUTTON_CHIPS.sort, rule[:selectors].sort
  end

  test "the question columns are split by an offset hairline that vanishes on one column" do
    pane = rule_for(".qf-main-wide .qf-pane + .qf-pane")
    assert_match(/position:\s*relative/, pane[:declarations],
      "the divider is a pseudo-element, so its pane has to be the containing block")
    assert_no_match(/padding|margin/, pane[:declarations],
      "the comments pane offsets its sticky head with negative margins — a padded pane breaks it")

    divider = rule_for(DIVIDER)
    assert_match(/content:\s*(""|none)/, divider[:declarations])
    assert_match(/position:\s*absolute/, divider[:declarations])
    assert_match(/inset-block:\s*0/, divider[:declarations], "the hairline spans the whole column height")
    assert_match(/inline-size:\s*1px/, divider[:declarations])
    assert_match(/background:[^;]*var\(--qf-border\)/, divider[:declarations],
      "the divider is a muted border colour, never a hardcoded one")

    gap = rule_for(".qf-main-wide .qf-panes")[:declarations][/gap:\s*([\d.]+)px/, 1].to_f
    offset = divider[:declarations][/inset-inline-start:\s*-([\d.]+)px/, 1].to_f
    assert gap.positive?, "the wide panes must declare a px gap to divide"
    assert_operator (offset - gap / 2).abs, :<=, 1,
      "a 1px line sits dead centre of the #{gap}px gap, so the offset is about #{-gap / 2}px, got #{-offset}px"

    narrow = rules.select { |rule| narrow_media?(rule[:media]) && rule[:selectors].include?(DIVIDER) }
    assert_not_empty narrow, "the divider must be switched off in the max-width: 1000px one-column layout"
    narrow.each do |rule|
      assert_match(/content:\s*none/, rule[:declarations],
        "one column has no gap left to divide, so #{rule[:media]} has to drop the hairline")
    end
  end

  test "the urgency badge colours come from :root vars and stay readable" do
    root = rules.find { |rule| rule[:selectors].include?(":root") }
    assert_not_nil root, "the palette lives in a :root block"

    ink = css_color(root[:declarations], "--qf-urgent")
    background = css_color(root[:declarations], "--qf-urgent-bg")
    assert_match(/\A#[0-9a-f]{6}\z/, ink, "--qf-urgent must be a hex colour, got #{ink.inspect}")
    assert_match(/\A#[0-9a-f]{6}\z/, background, "--qf-urgent-bg must be a hex colour")

    chip = rule_for(URGENT_CHIP)
    assert_match(/color:\s*var\(--qf-urgent\)/, chip[:declarations],
      "the badge colour must be referenced, not repeated as a literal")
    assert_match(/background:\s*var\(--qf-urgent-bg\)/, chip[:declarations])

    ratio = contrast(ink, background)
    assert_operator ratio, :>=, MIN_CONTRAST,
      "badge text #{ink} on #{background} is #{ratio.round(2)}:1, below #{MIN_CONTRAST}:1"
  end

  private

  def stylesheet
    @stylesheet ||= Rails.root.join(STYLE_SHEET).read.gsub(%r{/\*.*?\*/}m, "")
  end

  # Flat list of leaf rules as { media:, selectors:, declarations: }; at-rule
  # preludes (@media) are pushed onto the rules they wrap.
  def rules
    @rules ||= parse(stylesheet)
  end

  def parse(source, media = nil)
    found = []
    rest = source.dup
    until rest.empty?
      open_at = rest.index("{")
      break if open_at.nil?

      prelude = rest[0...open_at].strip
      close_at = closing_brace(rest, open_at)
      body = rest[(open_at + 1)...close_at]
      rest = rest[(close_at + 1)..]

      if prelude.start_with?("@")
        found.concat(parse(body, prelude))
      elsif !prelude.start_with?("}")
        found << { media: media, selectors: prelude.split(",").map(&:strip), declarations: body }
      end
    end
    found
  end

  def closing_brace(source, open_at)
    depth = 0
    source.each_char.with_index do |char, index|
      next if index < open_at
      depth += 1 if char == "{"
      depth -= 1 if char == "}"
      return index if depth.zero?
    end
    flunk "unbalanced braces in #{STYLE_SHEET}"
  end

  def rule_for(selector)
    rule = rules.find { |candidate| candidate[:selectors].include?(selector) }
    assert_not_nil rule, "#{STYLE_SHEET} must declare a rule for #{selector}"
    rule
  end

  def narrow_media?(media)
    media&.match?(/max-width:\s*([\d.]+)px/) && media[/max-width:\s*([\d.]+)px/, 1].to_f <= 1000
  end

  def css_color(declarations, variable)
    declarations[/#{Regexp.escape(variable)}:\s*(#[0-9a-fA-F]{3,8})/, 1]&.downcase
  end

  def contrast(foreground, background)
    lighter, darker = [ foreground, background ].map { luminance(_1) }.minmax.reverse
    (lighter + 0.05) / (darker + 0.05)
  end

  def luminance(hex)
    channels = hex.delete_prefix("#").scan(/../).map { Integer(_1, 16) / 255.0 }
    linear = channels.map { _1 <= 0.04045 ? _1 / 12.92 : ((_1 + 0.055) / 1.055)**2.4 }
    0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]
  end
end
