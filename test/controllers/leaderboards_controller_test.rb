require "test_helper"

class LeaderboardsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as(@user)
  end

  test "guest is redirected to sign in" do
    sign_out
    get leaderboard_path

    assert_redirected_to new_session_path
  end

  test "ranks closed correct verdicts, marks top3, ignores open questions" do
    Attempt.create!(question: questions(:closed_single), user: users(:one), selected: [ "0" ])
    Attempt.create!(question: questions(:closed_multiple), user: users(:one), selected: [ "0", "1" ])
    Attempt.create!(question: questions(:closed_single), user: users(:two), selected: [ "1" ])
    Attempt.create!(question: questions(:closed_text), user: users(:two), body: "x", verdict: "correct")
    Attempt.create!(question: questions(:open_text), user: users(:two), body: "x", verdict: "correct")
    get leaderboard_path

    assert_response :success
    assert_select "h1.qf-hero", text: "Лидеры"
    rows = assert_select(".qf-board .qf-row")
    assert_equal "One", rows[0].at_css(".qf-who").text
    assert_equal "2", rows[0].at_css(".qf-score").text
    assert_select ".qf-row.is-top1 .qf-who", text: "One"
    assert_select ".qf-row.is-top2 .qf-who", text: "Two"
    assert_select ".qf-row.is-me .qf-who", text: "One"
    assert_select ".qf-me-card", count: 0
  end

  test "filters by difficulty" do
    Attempt.create!(question: questions(:closed_single), user: users(:one), selected: [ "0" ])
    Attempt.create!(question: questions(:closed_multiple), user: users(:two), selected: [ "0", "1" ])
    get leaderboard_path, params: { difficulty: "легкое" }

    assert_select ".qf-board .qf-row", count: 1
    assert_select ".qf-row .qf-who", text: "One"
  end

  test "outsider sees own position card" do
    20.times do |i|
      rival = User.create!(name: "Rival#{i}", email: "rival#{i}@example.com",
                           password: "password12345678", password_confirmation: "password12345678")
      Attempt.create!(question: questions(:closed_single), user: rival, selected: [ "0" ])
      Attempt.create!(question: questions(:closed_multiple), user: rival, selected: [ "0", "1" ])
      Attempt.create!(question: questions(:closed_text), user: rival, body: "x", verdict: "correct")
    end
    Attempt.create!(question: questions(:closed_single), user: users(:one), selected: [ "0" ])
    get leaderboard_path

    assert_select ".qf-board .qf-row", count: 20
    assert_select ".qf-me-card .qf-pos", text: "#21"
    assert_select ".qf-me-card .qf-score", text: "1"
  end

  test "scoreless user gets dash place" do
    Attempt.create!(question: questions(:closed_single), user: users(:two), selected: [ "0" ])
    get leaderboard_path

    assert_select ".qf-board .qf-row", count: 1
    assert_select ".qf-me-card .qf-pos", text: "#-"
  end
end
