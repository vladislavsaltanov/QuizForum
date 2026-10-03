require "test_helper"

class QuestionTest < ActiveSupport::TestCase
  setup do
    @author = users(:one)
  end

  test "drops blank option rows before grading" do
    q = Question.create!(title: "t", body: "b", answer_type: "single_choice",
      options: [ { "text" => "a", "correct" => true }, { "text" => "  ", "correct" => false }, { "text" => "b", "correct" => false } ],
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_equal [ "a", "b" ], q.options.map { |o| o["text"] }
  end

  test "rejects title over 200 chars" do
    q = Question.new(title: "x" * 201, body: "b", answer_type: "text",
      reference_answer: "r", deadline: 7.days.from_now, author: @author)

    assert_not q.valid?
    assert q.errors[:title].any?
  end

  test "rejects body over 20000 chars" do
    q = Question.new(title: "t", body: "x" * 20_001, answer_type: "text",
      reference_answer: "r", deadline: 7.days.from_now, author: @author)

    assert_not q.valid?
  end

  test "rejects more than six options" do
    opts = 7.times.map { |i| { "text" => "o#{i}", "correct" => i.zero? } }
    q = Question.new(title: "t", body: "b", answer_type: "single_choice", options: opts,
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_not q.valid?
  end

  test "grants observers for known emails" do
    q = questions(:open_text)

    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails("two@example.com")
    assert_equal [ users(:two) ], q.reload.trustees.to_a
  end

  test "revokes observers dropped from the list" do
    q = questions(:open_text)
    dropped = User.create!(name: "Three", email: "three@example.com", password: "password-12-plus")
    QuestionTrustee.create!(question: q, user: users(:two))
    QuestionTrustee.create!(question: q, user: dropped)

    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails("two@example.com")
    assert_equal [ users(:two) ], q.reload.trustees.to_a
  end

  test "removes every observer for a blank field" do
    q = questions(:open_text)
    QuestionTrustee.create!(question: q, user: users(:two))

    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails(nil)
    assert_equal 0, QuestionTrustee.where(question: q).count
  end

  test "re-grants observers after the whole set was removed" do
    q = questions(:open_text)
    q.sync_trustees_by_emails("two@example.com")
    q.trustees.to_a # loaded association must not poison the next sync
    q.sync_trustees_by_emails("")

    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails("two@example.com")
    assert_equal [ users(:two) ], q.reload.trustees.to_a
  end

  test "keeps current observers when the new list cannot be granted" do
    q = questions(:open_text)
    QuestionTrustee.create!(question: q, user: users(:two))

    # The author can never be a trustee, so the grant is rejected.
    ok, alert = q.sync_trustees_by_emails(q.author.email)

    assert_equal [ false, "Добавлено наблюдателей: 0 из 1." ], [ ok, alert ]
    assert_equal [ users(:two) ], q.reload.trustees.to_a, "existing observer must survive a rejected grant"
  end

  test "still grants the resolvable half of a partly unknown list" do
    q = questions(:open_text)

    ok, alert = q.sync_trustees_by_emails("nobody@example.com, two@example.com")

    assert_equal [ false, "Добавлено наблюдателей: 1 из 2." ], [ ok, alert ]
    assert_equal [ users(:two) ], q.reload.trustees.to_a
  end

  test "folds case, whitespace and duplicates into one grant" do
    q = questions(:open_text)

    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails("  TWO@Example.com , two@example.com, ")
    assert_equal 1, QuestionTrustee.where(question: q).count
  end

  test "names the address and the reason for every rejected grant" do
    q = questions(:open_text)

    _, _, problems = q.sync_trustees_by_emails("ghost@example.com, #{q.author.email}, two@example.com")

    assert_includes problems, "ghost@example.com — нет пользователя с таким email"
    assert_includes problems, "#{q.author.email} — это вы, автор вопроса"
    assert_equal 2, problems.size
  end

  test "no problems means an empty third element" do
    q = questions(:open_text)

    assert_equal [], q.sync_trustees_by_emails("two@example.com").last
  end

  test "repeating the same list does not duplicate grants" do
    q = questions(:open_text)

    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails("two@example.com")
    assert_equal [ true, nil, [] ], q.sync_trustees_by_emails("two@example.com")
    assert_equal 1, QuestionTrustee.where(question: q).count
  end

  test "rejects multiple choice without correct option" do
    q = Question.new(title: "t", body: "b", answer_type: "multiple_choice",
      options: [ { "text" => "a", "correct" => false }, { "text" => "b", "correct" => false } ],
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_not q.valid?
  end
end
