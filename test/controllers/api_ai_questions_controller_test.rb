require "test_helper"

class ApiAiQuestionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @old_token = ENV["AI_INGEST_TOKEN"]
    ENV["AI_INGEST_TOKEN"] = "secret-token"
    AiQuestions.bot_user!
  end

  teardown do
    ENV["AI_INGEST_TOKEN"] = @old_token
  end

  test "guest without a token is unauthorized, not redirected" do
    post api_ai_questions_path, params: { batch_date: AiQuestions.today.to_s, questions: pack_items }

    assert_response :unauthorized
    assert_equal 0, Question.ai.count
  end

  test "wrong token is unauthorized" do
    post api_ai_questions_path, params: { batch_date: AiQuestions.today.to_s, questions: pack_items },
         headers: { "Authorization" => "Bearer wrong" }

    assert_response :unauthorized
  end

  test "valid token creates the pack" do
    post api_ai_questions_path, params: { batch_date: AiQuestions.today.to_s, questions: pack_items },
         headers: { "Authorization" => "Bearer secret-token" }

    assert_response :created
    assert_equal 9, response.parsed_body["ids"].size
    assert_equal 9, Question.ai.count
  end

  test "missing batch_date means today" do
    post api_ai_questions_path, params: { questions: pack_items },
         headers: { "Authorization" => "Bearer secret-token" }

    assert_response :created
    assert_equal AiQuestions.today.to_s, response.parsed_body["batch_date"]
  end

  test "repeat submit is a conflict" do
    auth = { "Authorization" => "Bearer secret-token" }
    args = { batch_date: AiQuestions.today.to_s, questions: pack_items }
    post(api_ai_questions_path, params: args, headers: auth)

    post(api_ai_questions_path, params: args, headers: auth)

    assert_response :conflict
    assert_equal 9, Question.ai.count
  end

  test "garbage batch_date is unprocessable" do
    post api_ai_questions_path, params: { batch_date: "когда-нибудь", questions: pack_items },
         headers: { "Authorization" => "Bearer secret-token" }

    assert_response :unprocessable_entity
  end

  test "kill switch closes the endpoint" do
    old = ENV["AI_QUESTIONS_ENABLED"]
    ENV["AI_QUESTIONS_ENABLED"] = "0"

    post api_ai_questions_path, params: { batch_date: AiQuestions.today.to_s, questions: pack_items },
         headers: { "Authorization" => "Bearer secret-token" }

    assert_response :not_found
  ensure
    ENV["AI_QUESTIONS_ENABLED"] = old
  end

  private
    def pack_items
      levels = %w[легкое среднее сложное]
      Array.new(9) do |i|
        { title: "Вебхук-вопрос #{i}", body: "Условие #{i}", answer_type: "text",
          reference_answer: "Ответ #{i}", explanation: "Разбор #{i}",
          difficulty: levels[i / 3], topics: [ "тема#{i}" ] }
      end
    end
end
