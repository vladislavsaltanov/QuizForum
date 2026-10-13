require "test_helper"

class TestTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
    @stranger = users(:two)
    @test = @author.authored_tests.create!(title: "Мидтерм", deadline: 1.day.from_now, published: true)
    @q0 = @test.questions.create!(title: "Текст?", body: "b", answer_type: "text",
      reference_answer: "да", deadline: @test.deadline, author: @author, points: 3, position: 0)
    @q1 = @test.questions.create!(title: "Выбор?", body: "b", answer_type: "single_choice",
      reference_answer: "", deadline: @test.deadline, author: @author, points: 4, position: 1,
      options: [ { "text" => "4", "correct" => true }, { "text" => "5", "correct" => false } ])
  end

  test "editable_by? admits the author and admins only" do
    admin = User.create!(name: "Админ", email: "admin-edit@example.com", password: "password-12-plus",
      email_confirmed_at: Time.current, admin: true)

    assert @test.editable_by?(@author)
    assert @test.editable_by?(admin)
    assert_not @test.editable_by?(@stranger)
    assert_not @test.editable_by?(nil)
  end

  test "home_feed exposes only published open tests without a password" do
    closed = @author.authored_tests.create!(title: "Закрытый", deadline: 1.day.ago, published: true)
    protected_test = @author.authored_tests.create!(title: "С паролем", deadline: 1.day.from_now,
      published: true, password: "secret")
    draft = @author.authored_tests.create!(title: "Черновик", deadline: 1.day.from_now)

    feed = Test.home_feed

    assert_includes feed, @test
    assert_not_includes feed, closed
    assert_not_includes feed, protected_test
    assert_not_includes feed, draft
  end

  test "home_feed orders open tests by nearest deadline" do
    later = @author.authored_tests.create!(title: "Позже", deadline: 3.days.from_now, published: true)

    assert_equal [@test, later].map(&:deadline), Test.home_feed.map(&:deadline)
  end

  test "taken_by returns only tests whose questions the user answered" do
    undone = @author.authored_tests.create!(title: "Нерешённый", deadline: 1.day.from_now, published: true)
    @q0.attempts.create!(user: @stranger, body: "да", verdict: "correct")

    taken = Test.taken_by(@stranger)

    assert_includes taken, @test
    assert_not_includes taken, undone
    assert_empty Test.taken_by(@author)
  end

  test "total_score treats a question without an attempt as zero" do
    @q0.attempts.create!(user: @stranger, body: "да", verdict: "correct")

    assert_equal 3, @test.total_score(@stranger)
  end
end
