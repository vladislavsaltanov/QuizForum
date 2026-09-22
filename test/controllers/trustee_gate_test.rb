require "test_helper"

class TrusteeGateTest < ActionDispatch::IntegrationTest
  setup do
    @question = questions(:open_text) # author: users(:one), open, text type
    @trustee = users(:two)
    @question.question_trustees.create!(user: @trustee)
  end

  test "trustee sees attempt texts and reference before deadline" do
    Attempt.create!(question: @question, user: users(:one), body: "sekret-text")
    sign_in_as(@trustee)
    get question_path(@question)

    assert_response :success
    assert_match(/sekret-text/, response.body)
    assert_match(/префикс-функцию/, response.body)
  end

  test "outsider still blind before deadline" do
    Attempt.create!(question: @question, user: users(:one), body: "sekret-text")
    outsider = User.create!(name: "Out", email: "out@example.com", password: "0123456789ab")
    sign_in_as(outsider)
    get question_path(@question)

    assert_response :success
    assert_no_match(/sekret-text/, response.body)
    assert_no_match(/префикс-функцию/, response.body)
  end

  test "author cannot be own trustee" do
    grant = @question.question_trustees.build(user: users(:one))

    assert_not grant.valid?
  end

  test "double grant rejected" do
    assert_raises(ActiveRecord::RecordInvalid) do
      @question.question_trustees.create!(user: @trustee)
    end
  end
end
