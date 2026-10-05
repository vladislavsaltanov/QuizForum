require "test_helper"

class AiFeedArchiveTest < ActionDispatch::IntegrationTest
  test "feed shows one AI banner linking to the rubric, no pack cards in the loop" do
    sign_in_as(users(:one))
    Question.create!(title: "Людской вопрос", body: "Тело", answer_type: "text",
                             reference_answer: "Ответ", deadline: 7.days.from_now,
                             author: users(:one), tags: [ "программирование" ])
    AiQuestionIngest.call(items: pack_items)

    get root_path

    assert_response :success
    assert_select ".qf-ai-banner-link[href=?]", ai_pack_path, count: 1
    assert_select ".qf-ai-banner", count: 1
    assert_select ".qf-ai-banner-sub", count: 1
    assert_select "main .qf-card-title", text: /Пак-вопрос/, count: 0
    assert_select "main .qf-card-title", text: "Людской вопрос", count: 1
  end

  test "rubric page lists the pack grouped by difficulty" do
    sign_in_as(users(:one))
    AiQuestionIngest.call(items: pack_items)

    get ai_pack_path

    assert_response :success
    assert_select "h1.qf-hero", text: "Вопросы дня"
    assert_select ".qf-ai-level", count: 3
    assert_select ".qf-card", count: 9
    assert_select ".qf-card-title", text: /Пак-вопрос 0 \(#{Date.current.strftime("%d.%m")}\)/
  end

  test "rubric page redirects home when there is no pack" do
    sign_in_as(users(:one))

    get ai_pack_path

    assert_redirected_to root_path
  end

  test "feed hides the banner with the kill switch off" do
    sign_in_as(users(:one))
    AiQuestionIngest.call(items: pack_items)
    old = ENV["AI_QUESTIONS_ENABLED"]
    ENV["AI_QUESTIONS_ENABLED"] = "0"

    get root_path

    assert_select ".qf-ai-banner", count: 0
    assert_select ".qf-card-title", text: /Пак-вопрос/, count: 0

    get ai_pack_path

    assert_redirected_to root_path
  ensure
    ENV["AI_QUESTIONS_ENABLED"] = old
  end

  test "feed hides the banner when the cookie is set" do
    sign_in_as(users(:one))
    AiQuestionIngest.call(items: pack_items)
    patch toggle_ai_banner_profile_path, params: { hide_ai_banner: "1" }

    get root_path

    assert_response :success
    assert_select ".qf-ai-banner", count: 0

    patch toggle_ai_banner_profile_path

    get root_path

    assert_select ".qf-ai-banner", count: 1
  end

  test "archive defaults to humans only, with Все/Без ИИ/Только ИИ switch" do
    sign_in_as(users(:one))
    pack = ai_archived("Архивный пак")
    Question.create!(title: "Архивный людской", body: "Тело", answer_type: "text",
                             reference_answer: "Ответ", deadline: Question::ARCHIVE_GRACE.ago - 1.day,
                             author: users(:one), tags: [ "среднее" ])

    get archive_path
    assert_select ".qf-card-title", text: "Архивный людской", count: 1
    assert_select ".qf-card-title", text: /Архивный пак/, count: 0
    assert_select "nav.qf-tabs a", text: "Все", count: 1
    assert_select "nav.qf-tabs a", text: "Без ИИ", count: 1
    assert_select "nav.qf-tabs a", text: "Только ИИ", count: 1

    get archive_path, params: { ai: "all" }
    assert_select ".qf-card-title", text: "Архивный людской", count: 1
    assert_select ".qf-card-title", text: /#{Regexp.escape(pack.title)} \(#{pack.created_at.strftime("%d.%m")}\)/, count: 1

    get archive_path, params: { ai: "1" }
    assert_select ".qf-card-title", text: /#{Regexp.escape(pack.title)} \(#{pack.created_at.strftime("%d.%m")}\)/, count: 1
    assert_select ".qf-card-title", text: "Архивный людской", count: 0
  end

  test "archive hides the ИИ tab with the kill switch off" do
    sign_in_as(users(:one))
    old = ENV["AI_QUESTIONS_ENABLED"]
    ENV["AI_QUESTIONS_ENABLED"] = "0"

    get archive_path

    assert_select "nav.qf-tabs", count: 0
  ensure
    ENV["AI_QUESTIONS_ENABLED"] = old
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

    def ai_archived(title)
      Question.create!(title: title, body: "Тело", answer_type: "text",
                       reference_answer: "Ответ", deadline: 3.hours.ago,
                       author: users(:one), tags: [ "ИИ", "среднее" ],
                       ai_generated: true, ai_batch: AiQuestions.today)
    end
end
