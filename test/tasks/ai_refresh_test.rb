require "test_helper"
require "rake"

Rails.application.load_tasks unless Rake::Task.task_defined?("ai:refresh")

class AiRefreshTaskTest < ActiveSupport::TestCase
  setup do
    Rake::Task["ai:refresh"].reenable
  end

  test "wipes open AI packs, keeps humans and revealed packs, regenerates today" do
    old_pack = AiQuestions.today - 5
    Question.create!(title: "Старый ИИ", body: "Тело", answer_type: "text",
      deadline: 7.days.from_now, reference_answer: "Ответ",
      author: users(:one), ai_generated: true, ai_batch: old_pack)
    revealed = Question.create!(title: "Раскрытый ИИ", body: "Тело", answer_type: "text",
      deadline: 1.day.ago, reference_answer: "Ответ",
      author: users(:one), ai_generated: true, ai_batch: old_pack)
    human = Question.create!(title: "Живой", body: "Тело", answer_type: "text",
      deadline: 7.days.from_now, reference_answer: "Ответ", author: users(:one))

    ENV["GEMINI_API_KEY"] = "test-key"
    GeminiClient.define_singleton_method(:new) do
      Object.new.tap do |client|
        def client.generate_pack(**_)
          levels = %w[легкое среднее сложное]
          Array.new(9) do |i|
            { title: "Свежий #{i}", body: "Условие #{i}", answer_type: "text",
              reference_answer: "Ответ #{i}", explanation: "Разбор #{i}",
              difficulty: levels[i / 3], topics: [ "тема#{i}" ] }
          end
        end
      end
    end

    Rake::Task["ai:refresh"].invoke

    assert_equal 9, Question.ai.where(ai_batch: AiQuestions.today).count
    assert Question.exists?(human.id)
    assert Question.exists?(revealed.id)
  ensure
    ENV.delete("GEMINI_API_KEY")
    class << GeminiClient
      remove_method :new
    end
  end
end
