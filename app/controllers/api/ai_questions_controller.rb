# Provider-agnostic AI pack intake: any generator (AI Studio prompt, n8n, Gemini job)
# POSTs one JSON pack per day; intake still passes the human moderation bar.
module Api
  class AiQuestionsController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_before_action :verify_authenticity_token, only: :create
    skip_before_action :allow_browser, only: :create, raise: false

    rate_limit to: 10, within: 10.minutes, only: :create,
               with: -> { render json: { errors: [ "Попробуйте позже." ] }, status: :too_many_requests }

    # Creates the whole 9-pack or nothing; per-item problems come back as strings.
    def create
      return render json: { errors: [ "AI выключен." ] }, status: :not_found unless AiQuestions.enabled?
      return render json: { errors: [ "Нет доступа." ] }, status: :unauthorized unless authorized?
      batch = parse_batch
      return render json: { errors: [ "batch_date — дата ГГГГ-ММ-ДД." ] }, status: :unprocessable_entity if batch.nil?
      result = AiQuestionIngest.call(items: pack_params, batch:)
      if result.errors.empty?
        render json: { batch_date: batch.to_s, ids: result.questions.map(&:id) }, status: :created
      else
        render json: { errors: result.errors }, status: result.conflict ? :conflict : :unprocessable_entity
      end
    end

    private
      # Bearer token compared in constant time; blank server token closes the door.
      def authorized?
        expected = AiQuestions.ingest_token
        return false if expected.empty?
        provided = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
        ActiveSupport::SecurityUtils.secure_compare(provided, expected)
      end

      # Missing date means today in the AI zone; garbage means 422, never 500.
      def parse_batch
        raw = pack_root[:batch_date].to_s.strip
        return AiQuestions.today if raw.empty?
        Date.iso8601(raw)
      rescue Date::Error
        nil
      end

      # Whitelisted pack shape; anything else never reaches the ingest as a hash.
      def pack_root
        params.permit(:batch_date, questions: [
          :title, :body, :answer_type, :reference_answer, :explanation, :difficulty,
          { topics: [], options: [ :text, :correct ] }
        ])
      end

      def pack_params
        pack_root[:questions] || []
      end
  end
end
