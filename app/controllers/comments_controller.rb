# Premoderated comments; Laya sync-gate rejects toxic before INSERT.
# Comments hang on a Question (nested under questions) or on a Test
# (nested under tests); both branches share the same moderation bar.
class CommentsController < ApplicationController
  BATCH = 10

  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_back fallback_location: root_path, alert: "Попробуйте позже." }

  # Older batch prepended when the reader scrolls the chat up; the cursor is the
  # id of the oldest comment already on screen.
  def index
    @question = Question.find(params[:question_id])
    scope = Comment.visible_for(@question, Current.user).order(id: :desc)
    scope = scope.where("comments.id < ?", params[:before].to_i) if params[:before].present?
    # One extra row tells us whether another batch is waiting behind this one.
    batch = scope.limit(BATCH + 1).to_a
    @older = batch.first(BATCH).reverse
    @exhausted = batch.size <= BATCH
    # The cursor endpoint only ever answers Turbo; a stray bookmark gets nothing.
    head(:no_content) unless request.format.turbo_stream?
  end

  # Posts a comment; Laya pass publishes immediately, review stays pending.
  def create
    if params[:test_id].present?
      create_for_test
    else
      create_for_question
    end
  end

  # Publishes a comment; author, trustee, or admin only.
  def approve
    @comment = Comment.find(params[:id])
    return head(:forbidden) unless @comment.owner.privileged?(Current.user)
    @comment.update!(status: "approved")
    redirect_to owner_path(@comment), notice: "Комментарий опубликован."
  end

  # Deletes a comment; author, trustee, or admin only.
  def destroy
    @comment = Comment.find(params[:id])
    return head(:forbidden) unless @comment.owner.privileged?(Current.user)
    @comment.destroy!
    redirect_to owner_path(@comment), notice: "Комментарий удалён."
  end

  private
    def create_for_question
      @question = Question.find(params[:question_id])
      @comment = @question.comments.build(body: params.dig(:comment, :body), user: Current.user)
      unless @comment.valid?
        return redirect_to question_path(@question, tab: "comments"), alert: @comment.errors.full_messages.to_sentence
      end
      # Double clicks land on the existing row instead of a second check.
      if @question.comments.where(user: Current.user, body: @comment.body)
                   .where("created_at > ?", 30.seconds.ago).exists?
        return redirect_to question_path(@question, tab: "comments")
      end
      verdict = ModerationClient.check(text: @comment.body, question: @question.title)
      if verdict.verdict == :reject
        redirect_to question_path(@question, tab: "comments"), alert: "Комментарий отклонён: #{verdict.category}."
      elsif verdict.verdict == :try_later
        redirect_to question_path(@question, tab: "comments"), alert: "Проверка не удалась, попробуйте позже."
      else
        @comment.status = "approved" if verdict.verdict == :pass
        if @comment.save
          redirect_to question_path(@question, tab: "comments")
        else
          redirect_to question_path(@question, tab: "comments"), alert: @comment.errors.full_messages.to_sentence
        end
      end
    end

    # Test branch: drafts take no comments, moderation body shared.
    def create_for_test
      @test = Test.find(params[:test_id])
      path = test_path(@test)
      return redirect_to path, alert: "Тест ещё не опубликован." unless @test.published?
      @comment = @test.comments.build(body: params.dig(:comment, :body), user: Current.user)
      unless @comment.valid?
        return redirect_to path, alert: @comment.errors.full_messages.to_sentence
      end
      if @test.comments.where(user: Current.user, body: @comment.body)
              .where("created_at > ?", 30.seconds.ago).exists?
        return redirect_to path
      end
      verdict = ModerationClient.check(text: @comment.body, question: @test.title)
      if verdict.verdict == :reject
        redirect_to path, alert: "Комментарий отклонён: #{verdict.category}."
      elsif verdict.verdict == :try_later
        redirect_to path, alert: "Проверка не удалась, попробуйте позже."
      else
        @comment.status = "approved" if verdict.verdict == :pass
        if @comment.save
          # Stream response keeps the page put: the new bubble arrives via the
          # broadcasting channel, only the composer itself is re-rendered.
          respond_to do |format|
            format.html { redirect_to path }
            format.turbo_stream { render turbo_stream: turbo_stream.replace("test-chatbar",
            partial: "comments/composer", locals: { post_path: test_comments_path(@test), form_id: "test-chatbar" }) }
          end
        else
          redirect_to path, alert: @comment.errors.full_messages.to_sentence
        end
      end
    end

    # Where the comment lives decides where the action returns.
    def owner_path(comment)
      comment.question ? [ comment.question, tab: "comments" ] : comment.test
    end
end
