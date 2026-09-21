class CommentsController < ApplicationController
  def create
    @question = Question.find(params[:question_id])
    @comment = @question.comments.build(body: params.dig(:comment, :body), user: Current.user)
    if @comment.save
      redirect_to question_path(@question, tab: "comments")
    else
      redirect_to question_path(@question, tab: "comments"), alert: @comment.errors.full_messages.to_sentence
    end
  end

  def approve
    @comment = Comment.find(params[:id])
    return head(:forbidden) unless @comment.question.author == Current.user || Current.user&.admin?
    @comment.update!(status: "approved")
    redirect_to question_path(@comment.question, tab: "comments"), notice: "Комментарий опубликован."
  end
end
