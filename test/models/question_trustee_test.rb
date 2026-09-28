require "test_helper"

class QuestionTrusteeTest < ActiveSupport::TestCase
  test "rejects author as own trustee" do
    question = questions(:open_text)
    grant = QuestionTrustee.new(question: question, user: question.author)

    assert_not grant.valid?
  end

  test "rejects duplicate grant" do
    QuestionTrustee.create!(question: questions(:open_text), user: users(:two))
    duplicate = QuestionTrustee.new(question: questions(:open_text), user: users(:two))

    assert_not duplicate.valid?
  end
end
