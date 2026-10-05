require "test_helper"

class AiQuestionIngestTest < ActiveSupport::TestCase
  # Production seeds the bot once; tests rebuild it per case under a passing verdict.
  setup { AiQuestions.bot_user! }

  test "creates the full 9-pack under the bot with server-set deadline and tags" do
    batch = AiQuestions.today

    questions, errors, conflict = AiQuestionIngest.call(items: pack_items, batch:).deconstruct

    assert_empty errors
    assert_not conflict
    assert_equal 9, questions.size
    assert_equal [ "Google Gemini" ], questions.map { it.author.name }.uniq
    assert_equal [ AiQuestions.deadline_for(batch) ], questions.map(&:deadline).uniq
    assert_equal [ batch ], questions.map(&:ai_batch).uniq
    assert questions.all? { it.tags.include?("ИИ") }
    assert_equal %w[легкое среднее сложное].sort, questions.map { it.tags & Question::DIFFICULTIES }.flatten.uniq.sort
  end

  test "second submit for the same batch is a conflict that creates nothing" do
    batch = AiQuestions.today
    AiQuestionIngest.call(items: pack_items, batch:)

    questions, _errors, conflict = AiQuestionIngest.call(items: pack_items, batch:).deconstruct

    assert_empty questions
    assert conflict
    assert_equal 9, Question.ai.where(ai_batch: batch).count
  end

  test "wrong pack size is rejected without creating anything" do
    questions, errors, _ = AiQuestionIngest.call(items: pack_items.first(3)).deconstruct

    assert_empty questions
    assert_equal 0, Question.ai.count
    assert_match(/Нужно 9 вопросов/, errors.first)
  end

  test "one rejected item rolls the whole pack back" do
    with_verdict(:reject, "спам") do
      questions, errors, _ = AiQuestionIngest.call(items: pack_items).deconstruct

      assert_empty questions
      assert_equal 0, Question.ai.count
      assert_equal 9, errors.size
    end
  end

  test "moderation outage fails closed without creating anything" do
    with_verdict(:try_later, "недоступна") do
      questions, errors, _ = AiQuestionIngest.call(items: pack_items).deconstruct

      assert_empty questions
      assert_equal 0, Question.ai.count
      assert_match(/Проверка не удалась/, errors.first)
    end
  end

  test "one invalid item rolls the whole pack back" do
    items = pack_items
    items[4][:title] = ""

    questions, errors, _ = AiQuestionIngest.call(items:).deconstruct

    assert_empty questions
    assert_equal 0, Question.ai.count
    assert_match(/Вопрос 5/, errors.first)
  end

  test "lopsided difficulties are rejected without creating anything" do
    items = pack_items
    items.each { it[:difficulty] = "легкое" }

    questions, errors, _ = AiQuestionIngest.call(items:).deconstruct

    assert_empty questions
    assert_equal 0, Question.ai.count
    assert_match(/по 3 вопроса каждой сложности/, errors.first)
  end

  test "choice items keep their options" do
    items = pack_items
    items[0].merge!(answer_type: "single_choice", reference_answer: "",
                    options: [ { text: "A", correct: true }, { text: "B", correct: false } ])

    questions, errors, _ = AiQuestionIngest.call(items:).deconstruct

    assert_empty errors
    assert_equal [ { "text" => "A", "correct" => true }, { "text" => "B", "correct" => false } ], questions.first.options
  end

  private
    def pack_items
      levels = %w[легкое среднее сложное]
      Array.new(9) do |i|
        { title: "Пак-вопрос #{i}", body: "Условие #{i}", answer_type: "text",
          reference_answer: "Ответ #{i}", explanation: "Разбор #{i}",
          difficulty: levels[i / 3], topics: [ "тема#{i}" ] }
      end
    end
end
