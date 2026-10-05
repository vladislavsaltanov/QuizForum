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

  test "rejects more than eight options" do
    opts = 9.times.map { |i| { "text" => "o#{i}", "correct" => i.zero? } }
    q = Question.new(title: "t", body: "b", answer_type: "single_choice", options: opts,
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert_not q.valid?
  end

  test "accepts eight options" do
    opts = 8.times.map { |i| { "text" => "o#{i}", "correct" => i.zero? } }
    q = Question.new(title: "t", body: "b", answer_type: "single_choice", options: opts,
      reference_answer: "r", deadline: 7.days.from_now, author: @author, tags: [])

    assert q.valid?
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

  test "closing soon means open with less than a day left" do
    assert timed_question("Скоро", 3.hours.from_now).closing_soon?
    assert_not timed_question("Не скоро", 5.days.from_now).closing_soon?
    assert_not timed_question("Уже закрыт", 3.hours.ago).closing_soon?
  end

  test "feed drops closed questions past the archive grace but keeps the weekly tail" do
    fresh_tail = timed_question("Хвост недели", 2.days.ago)
    ancient = timed_question("Древний", Question::ARCHIVE_GRACE.ago - 1.minute)

    titles = Question.feed.pluck(:title)

    assert_includes titles, fresh_tail.title
    assert_not_includes titles, ancient.title
  end

  test "feed lifts the closing cohort above the rest, nearest deadline first" do
    urgent_far = timed_question("Срочный, но позже", 20.hours.from_now)
    urgent_near = timed_question("Срочный и совсем скоро", 2.hours.from_now)
    calm = timed_question("Спокойный", 10.days.from_now)

    assert_equal [ urgent_near, urgent_far, calm ].map(&:title), feed_order_of(urgent_far, urgent_near, calm)
  end

  test "inside the calm tier the newer question wins" do
    older = timed_question("Старый открытый", 10.days.from_now)
    newer = timed_question("Свежий открытый", 9.days.from_now)
    stale = timed_question("Совсем старый открытый", 2.days.ago)

    assert_equal [ newer, older, stale ].map(&:title), feed_order_of(newer, older, stale)
  end

  test "archived keeps only closed past the grace period, newest closure first" do
    newest = timed_question("Недавно закрытый", Question::ARCHIVE_GRACE.ago - 1.hour)
    oldest = timed_question("Очень старый", 1.year.ago)
    tail = timed_question("Ещё в ленте", 1.day.ago)

    titles = Question.archived.where(title: [ newest.title, oldest.title, tail.title ]).pluck(:title)

    assert_equal [ newest, oldest ].map(&:title), titles
    assert_not_includes titles, tail.title
  end

  private
    def timed_question(title, deadline)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline: deadline,
                       author: @author, tags: [ "среднее" ])
    end

    # Fixtures also sit in the feed, so ordering assertions narrow to the questions under test.
    def feed_order_of(*questions)
      Question.feed.where(title: questions.map(&:title)).pluck(:title)
    end
end
