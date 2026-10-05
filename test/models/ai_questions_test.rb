require "test_helper"

class AiQuestionsTest < ActiveSupport::TestCase
  test "deadline_for is next day 15:00 in the AI zone" do
    deadline = AiQuestions.deadline_for(Date.new(2026, 10, 5))

    assert_equal Time.utc(2026, 10, 6, 12, 0), deadline
  end

  test "feed keeps open AI packs and the 2-hour closed tail only" do
    open_pack = ai_question("Открытый пак", deadline: 1.hour.from_now)
    tail_pack = ai_question("Хвост пака", deadline: 1.hour.ago)
    gone_pack = ai_question("Ушедший пак", deadline: 3.hours.ago)

    assert_includes Question.feed, open_pack
    assert_includes Question.feed, tail_pack
    assert_not_includes Question.feed, gone_pack
  end

  test "archived takes AI packs past the short grace" do
    gone_pack = ai_question("Ушедший пак", deadline: 3.hours.ago)

    assert_includes Question.archived, gone_pack
  end

  test "kill switch removes AI from feed and archive" do
    with_ai_disabled do
      pack = ai_question("Невидимый пак", deadline: 1.hour.from_now)
      old_pack = ai_question("Старый пак", deadline: 3.hours.ago)

      assert_not_includes Question.feed, pack
      assert_not_includes Question.archived, old_pack
    end
  end

  test "retention window defaults to 3 days" do
    assert_equal 3, AiQuestions.retention_days
  end

  private
    def ai_question(title, deadline:)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline:,
                       author: users(:one), tags: [ "ИИ", "среднее" ],
                       ai_generated: true, ai_batch: AiQuestions.today)
    end

    def with_ai_disabled
      old = ENV["AI_QUESTIONS_ENABLED"]
      ENV["AI_QUESTIONS_ENABLED"] = "0"
      yield
    ensure
      ENV["AI_QUESTIONS_ENABLED"] = old
    end
end
