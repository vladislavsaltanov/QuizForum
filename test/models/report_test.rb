require "test_helper"

class ReportTest < ActiveSupport::TestCase
  test "rejects duplicate report on same question" do
    Report.create!(question: questions(:open_text), user: users(:one))
    duplicate = Report.new(question: questions(:open_text), user: users(:one))

    assert_not duplicate.valid?
  end

  test "allows same user on different questions" do
    Report.create!(question: questions(:open_text), user: users(:one))
    other = Report.new(question: questions(:closed_text), user: users(:one))

    assert other.valid?
  end
end
