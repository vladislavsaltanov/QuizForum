require "test_helper"

# The polish pass is pure CSS, so no request renders it. These assertions read
# the stylesheet off disk and pin the rules a regression would silently drop:
# the UA underline on button-shaped links, the divider between the question-page
# columns, and the urgency badge colours.
class UiPolishTest < ActionDispatch::IntegrationTest
  STYLE_SHEET = "app/assets/stylesheets/application.css"
  BUTTON_CHIPS = %w[.qf-ghost .qf-tab .qf-chip].freeze
  DIVIDER = ".qf-main-wide .qf-panes::before"
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

  test "the question columns are split by a divider that outlasts the comments cap" do
    panes = rule_for(".qf-main-wide .qf-panes")
    assert_match(/position:\s*relative/, panes[:declarations],
      "the divider hangs off the grid, so the grid has to be its containing block")

    divider = rule_for(DIVIDER)
    assert_match(/content:\s*(""|none)/, divider[:declarations])
    assert_match(/position:\s*absolute/, divider[:declarations])

    # Regression guard: the comments pane caps its own height to the room below
    # the sticky head, so a divider attached to that pane stops at the chat
    # bottom. It has to hang off the grid instead.
    assert_empty rules.select { |rule| rule[:selectors].any? { _1.match?(/\.qf-pane(?![-\w])[^,{]*::before/) } },
      "no pane may carry a divider pseudo-element: the comments pane is height-capped"

    # The rule spans the middle 95% of the grid, dead centre. Both insets are
    # shares of the grid height and have to be equal, or the rule drifts off
    # centre and stops reading as a separator.
    top, bottom = divider[:declarations][/inset-block:\s*([^;]+)/, 1].to_s.split(/\s+/)
    [ top, bottom ].each do |value|
      assert_match(/\A[\d.]+%\z/, value,
        "both insets must be a share of the grid height, got #{top.inspect} #{bottom.inspect}")
    end
    assert_in_delta 0.025, top.to_s.delete("%").to_f / 100, 0.005,
      "the rule should span 0.95 of the panes, so 2.5% has to come off each end"
    assert_in_delta 0.025, bottom.to_s.delete("%").to_f / 100, 0.005
    assert_equal top, bottom,
      "the insets must match: #{top} and #{bottom} put the rule off centre"

    # The sticky comments head and the author card paint glass backgrounds. Below
    # them the rule vanishes under the tab bar, so it has to be on top.
    rule_z = divider[:declarations][/z-index:\s*(\d+)/, 1].to_i
    assert rule_z.positive?, "the rule needs an explicit z-index to stay visible over the sticky head"
    [ ".qf-list-head", ".qf-author-card" ].each do |selector|
      other = rules.find { |candidate| candidate[:selectors].include?(selector) }
      next if other.nil?

      z = other[:declarations][/z-index:\s*(\d+)/, 1].to_i
      assert_operator rule_z, :>, z,
        "#{selector} paints at z-index #{z}; the divider at #{rule_z} would be hidden behind it"
    end

    assert_match(/inline-size:\s*2px/, divider[:declarations], "the divider is a 2px rule")
    assert_match(/background:[^;]*var\(--qf-border\)/, divider[:declarations],
      "the divider is a muted border colour, never a hardcoded one")

    decls = panes[:declarations]
    gap = decls[/gap:\s*([\d.]+)px/, 1].to_f
    weights = decls.scan(/(\d+)fr/).flatten.map(&:to_i)
    assert gap.positive?, "the wide panes must declare a px gap to divide"
    assert_equal 2, weights.size, "expected a two-column split, got #{decls[/grid-template-columns:[^;]+/, 1]}"

    offset = divider[:declarations][/inset-inline-start:\s*([^;]+)/, 1].to_s
    # The grid has no inline padding, so the offset is a plain fraction of the
    # column box. No nested clamp()/var(): that form silently dropped the whole
    # declaration in the browser and parked the rule at the page edge.
    centred = (gap / 2 - 1).round
    assert_equal "calc((100% - #{gap.to_i}px) * #{weights.first} / #{weights.sum} + #{centred}px)", offset,
      "the rule must sit half a gap past the first column of #{weights.join(':')}, computed with plain numbers"
    assert_no_match(/var\(|clamp\(/, offset, "the offset must not depend on custom properties or clamp()")

    narrow = rules.select { |rule| narrow_media?(rule[:media]) && rule[:selectors].include?(DIVIDER) }
    assert_not_empty narrow, "the divider must be switched off in the max-width: 1000px one-column layout"
    narrow.each do |rule|
      assert_match(/content:\s*none/, rule[:declarations],
        "one column has no gap left to divide, so #{rule[:media]} has to drop the rule")
    end
  end

  test "the comments panes keep their negative margins" do
    pane = rule_for(".qf-pane")
    assert_no_match(/padding|margin/, pane[:declarations],
      "the comments pane offsets its sticky head with negative margins — a padded pane breaks it")
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

  test "the footer sits at the bottom of the viewport on a short page" do
    body = rules.select { |candidate| candidate[:selectors].include?("body") }
             .find { |candidate| candidate[:declarations].include?("margin:") }
    assert_not_nil body, "the main body block must still be there"
    assert_match(/min-block-size:\s*100dvh/, body[:declarations],
      "the page has to claim the viewport height, or there is no slack to push the footer down into")
    assert_match(/display:\s*flex/, body[:declarations])
    assert_match(/flex-direction:\s*column/, body[:declarations])

    main = rule_for(".qf-main")[:declarations]
    assert_match(/flex:\s*1 0 auto/, main,
      ".qf-main has to absorb the leftover height or the footer stays under the content")
    # An auto cross-axis margin cancels flex stretch, so without an explicit
    # width .qf-main collapses to its content width — the page goes to a sliver.
    assert_match(/inline-size:\s*100%/, main,
      ".qf-main needs an explicit width; margin-inline: auto cancels the flex stretch")
    assert_match(/box-sizing:\s*border-box/, main,
      "that width must include the inline padding, or the block overflows its container")
  end

  test "the tab row lines up with the top of the column" do
    head = rule_for(".qf-list-head")[:declarations]
    top_pad = head[/padding:\s*([^;]+)/, 1].to_s.split(/\s+/).first
    assert_equal "0", top_pad,
      "the author card starts at the top of the column; #{top_pad} of head padding pushes the tabs below it"
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
