require "test_helper"

# Per-respondent solved mark: plaque before Deadline, verdict dot after.
class SolvedBadgeTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "respondent sees solved plaque instead of time chip before deadline" do
    question = questions(:open_text)
    Attempt.create!(question: question, user: @user, body: "my answer")

    get root_path
    assert_response :success
    assert_select ".qf-card-meta .qf-chip", text: "решено"

    get question_path(question)
    assert_response :success
    assert_select ".qf-kicker .qf-chip", text: "решено"
    assert_select ".qf-author-card .qf-chip", text: "решено"
  end

  test "stranger sees time chip and no plaque before deadline" do
    question = questions(:open_text)
    Attempt.create!(question: question, user: users(:two), body: "someone else")

    get root_path
    assert_response :success
    assert_select ".qf-chip", text: "решено", count: 0
    assert_select ".qf-card-meta .qf-chip", text: /до /

    get question_path(question)
    assert_response :success
    assert_select ".qf-chip", text: "решено", count: 0
    assert_select ".qf-verdict-dot", count: 0
  end

  test "post-deadline respondent sees own verdict dot instead of time" do
    question = questions(:closed_single)
    Attempt.create!(question: question, user: users(:two), selected: [ "0" ])
    sign_in_as(users(:two))

    get question_path(question)
    assert_response :success
    assert_select ".qf-kicker .qf-verdict-dot.qf-verdict-correct", text: "✓"
    assert_select ".qf-author-card .qf-verdict-dot.qf-verdict-correct", text: "✓"
    # Existing verdict stream targets keep working.
    assert_select "#question-stats"
    assert_select "##{ActionView::RecordIdentifier.dom_id(Attempt.last, :my_verdict)}"
  end

  test "post-deadline pending attempt shows no circle" do
    question = questions(:closed_text)
    Attempt.create!(question: question, user: users(:two), body: "late answer")
    sign_in_as(users(:two))

    get question_path(question)
    assert_response :success
    assert_select ".qf-verdict-dot", count: 0
  end

  test "feed respondent marks cost one attempt query regardless of card count" do
    Attempt.create!(question: questions(:open_text), user: @user, body: "a1")
    Attempt.create!(question: questions(:open_code), user: @user, body: "a2")

    attempts_sql = []
    listener = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      attempts_sql << payload[:sql] if payload[:sql].include?("attempts")
    end
    get root_path
    ActiveSupport::Notifications.unsubscribe(listener)

    assert_response :success
    # Eager load of card counters + one solved-marks query; never per-card.
    assert_equal 2, attempts_sql.size, attempts_sql.inspect
  end

  test "closed feed card is marked inactive" do
    Question.create!(title: "just closed", body: "b", author: users(:two),
      answer_type: "text", reference_answer: "ref", deadline: 1.hour.ago)

    get root_path
    assert_response :success
    assert_select ".qf-card.is-closed", minimum: 1
  end
end
