require "test_helper"

class TrusteeGrantsTest < ActionDispatch::IntegrationTest
  setup do
    @question = questions(:open_text) # author: users(:one), open
    @author = users(:one)
    @candidate = users(:two)
  end

  test "create with comma-separated emails grants all" do
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "Новый вопрос", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_emails: "#{@candidate.email}, #{other.email}"
      }
    }

    q = Question.find_by!(title: "Новый вопрос")
    assert_redirected_to question_path(q)
    assert q.trustees.exists?(@candidate.id)
    assert q.trustees.exists?(other.id)
  end

  test "create with unknown email in list saves question, grants known, alerts" do
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "Вопрос частично", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_emails: "#{@candidate.email}, ghost@example.com"
      }
    }

    q = Question.find_by!(title: "Вопрос частично")
    assert_redirected_to question_path(q)
    assert q.trustees.exists?(@candidate.id)
    assert_no_match(/ghost@example.com/, flash[:alert])
    assert_match(/Добавлено наблюдателей: 1 из 2/, flash[:alert])
  end

  test "update replaces set: removing email revokes" do
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: other.email
      }
    }

    assert_redirected_to question_path(@question)
    assert_not @question.trustees.exists?(@candidate.id)
    assert @question.trustees.exists?(other.id)
  end

  test "update with blank field clears all" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: ""
      }
    }

    assert_redirected_to question_path(@question)
    assert_equal 0, @question.question_trustees.count
  end

  test "update with own email grants nothing and alerts" do
    sign_in_as(@author)
    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: @author.email
      }
    }

    assert_redirected_to question_path(@question)
    assert_not_nil flash[:alert]
    assert_match(/Добавлено наблюдателей: 0 из 1/, flash[:alert])
    assert_equal 0, @question.question_trustees.count
  end

  test "modal names the rejected address while the toast keeps the summary" do
    sign_in_as(@author)
    post questions_path, params: {
      question: {
        title: "С модалкой", body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_emails: "ghost@example.com"
      }
    }

    assert_equal [ "ghost@example.com — нет пользователя с таким email" ], flash[:modal]
    assert_match(/Добавлено наблюдателей: 0 из 1/, flash[:alert])

    q = Question.find_by!(title: "С модалкой")
    assert_redirected_to question_path(q)

    follow_redirect!
    assert_select "dialog#qf-modal li", text: "ghost@example.com — нет пользователя с таким email"
  end

  test "a racing save lands as a modal instead of a 500" do
    sign_in_as(@author)

    assert_no_difference -> { Question.count } do
      with_broken_sync(ActiveRecord::RecordNotUnique.new("race")) { publish(title: "Гонка", trustee: @candidate.email) }
    end

    assert_equal [ "Параллельное сохранение: список наблюдателей не применён. Повторите правку." ], flash[:modal]
    assert_response :unprocessable_entity
    assert_match(/Не удалось сохранить/, response.body)
  end

  test "a crashing sync rolls the whole question save back" do
    sign_in_as(@author)

    assert_raises(RuntimeError) do
      with_broken_sync { publish(title: "Откат публикации", trustee: @candidate.email) }
    end

    assert_nil Question.find_by(title: "Откат публикации"), "question must not survive a failed sync"
  end

  test "a crashing sync rolls an update back too" do
    sign_in_as(@author)
    original_title = @question.title

    assert_raises(RuntimeError) do
      with_broken_sync { patch question_path(@question), params: edit_params(trustee: @candidate.email, title: "Переименован") }
    end

    assert_equal original_title, @question.reload.title, "edit must not survive a failed sync"
    assert_empty @question.question_trustees
  end

  test "trustee cannot edit question or change set" do
    other = User.create!(name: "Other", email: "other@example.com", password: "0123456789ab")
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@candidate)
    get edit_question_path(@question)

    assert_response :forbidden

    patch question_path(@question), params: {
      question: {
        title: @question.title, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: other.email
      }
    }

    assert_response :forbidden
    assert @question.trustees.exists?(@candidate.id)
    assert_not @question.trustees.exists?(other.id)
  end

  test "edit form shows field prefilled with current emails" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    get edit_question_path(@question)

    assert_response :success
    assert_match(/Наблюдатели/, response.body)
    assert_match(/#{@candidate.email}/, response.body)
  end

  test "show page has no management block" do
    @question.question_trustees.create!(user: @candidate)
    sign_in_as(@author)
    get question_path(@question)

    assert_response :success
    assert_no_match(/Наблюдатели/, response.body)
    assert_no_match(/Отозвать/, response.body)
  end

  private
    def publish(title:, trustee: nil)
      post questions_path, params: { question: {
        title:, body: "Текст", answer_type: "text",
        deadline: 7.days.from_now.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: "Эталон", trustee_emails: trustee
      } }
    end

    def edit_params(trustee: nil, title: @question.title)
      { question: { title:, body: @question.body, answer_type: "text",
        deadline: @question.deadline.strftime("%Y-%m-%dT%H:%M"),
        reference_answer: @question.reference_answer, trustee_emails: trustee } }
    end

    # Makes the sync die mid-transaction: a lost unique-index race, or any other crash.
    def with_broken_sync(error = RuntimeError.new("boom"))
      original = Question.instance_method(:sync_trustees_by_emails)
      Question.define_method(:sync_trustees_by_emails) { |*| raise error }
      yield
    ensure
      Question.define_method(:sync_trustees_by_emails, original)
    end
end
