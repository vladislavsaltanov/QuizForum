require "net/http"
require "json"

# Outgoing generation adapter #1 (Gemini). Returns an array of pack item hashes
# shaped for AiQuestionIngest, or nil when generation failed. Swap the adapter,
# not the ingest: the intake stays provider-agnostic.
class GeminiClient
  ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/models/%<model>s:generateContent"
  OPEN_TIMEOUT = 5
  # Gemma fallback thinks out loud; trivial prompts already take ~40s.
  READ_TIMEOUT = 300

  # Generates one 9-pack: 3 per difficulty, distinct topics, Russian.
  # recent_titles keeps the model from repeating the last packs.
  # Falls back to the spare model when the primary fails.
  def generate_pack(difficulties: Question::DIFFICULTIES, recent_titles: [])
    text = prompt(difficulties, recent_titles)
    [ self.class.model, self.class.fallback_model ].uniq.each do |model|
      Rails.logger.info("[Gemini] requesting pack from #{model}...")
      items = extract(request(text, model:), model:)
      if items.is_a?(Array) && items.size == AiQuestions::PACK_SIZE
        Rails.logger.info("[Gemini] #{model} returned #{items.size} items.")
        return items
      end
      Rails.logger.warn("[Gemini] #{model} gave no usable pack.")
    end
    Rails.logger.error("[Gemini] all models failed.")
    nil
  end

  def self.model
    ENV.fetch("GEMINI_MODEL", "gemini-3.5-flash-lite")
  end

  def self.fallback_model
    ENV.fetch("GEMINI_FALLBACK_MODEL", "gemma-4-31b-it")
  end

  private
    def prompt(difficulties, recent_titles)
      avoid = recent_titles.compact_blank.uniq.first(30)
      <<~TEXT
        Составь #{AiQuestions::PACK_SIZE} вопросов для квиз-форума на русском языке: по 3 каждой сложности (#{difficulties.join(", ")}), темы разные, без повторов.
        #{avoid.any? ? "Не повторяй эти темы и формулировки:\n#{avoid.map { "- #{it}" }.join("\n")}" : ""}
        Типы ответов: text (свободный текст с правильным ответом и объяснением) или single_choice (2-4 варианта, ровно один верный).
        Вопросы должны быть конкретными, с однозначным ответом, без подвоха ради подвоха.
      TEXT
    end

    def schema
      {
        type: "OBJECT",
        properties: {
          questions: {
            type: "ARRAY",
            items: {
              type: "OBJECT",
              properties: {
                title: { type: "STRING" },
                body: { type: "STRING" },
                answer_type: { type: "STRING" },
                reference_answer: { type: "STRING" },
                explanation: { type: "STRING" },
                difficulty: { type: "STRING" },
                topics: { type: "ARRAY", items: { type: "STRING" } },
                options: {
                  type: "ARRAY",
                  items: {
                    type: "OBJECT",
                    properties: { text: { type: "STRING" }, correct: { type: "BOOLEAN" } },
                    required: %w[text correct]
                  }
                }
              },
              required: %w[title body answer_type reference_answer difficulty topics]
            }
          }
        },
        required: %w[questions]
      }
    end

    def request(prompt_text, model:)
      uri = URI(format(ENDPOINT, model:))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT
      req = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json",
                                                     "x-goog-api-key" => ENV["GEMINI_API_KEY"].to_s)
      req.body = JSON.generate(contents: [ { parts: [ { text: prompt_text } ] } ],
                               generationConfig: { responseMimeType: "application/json", responseSchema: schema })
      res = http.request(req)
      unless res.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[Gemini] #{model} HTTP #{res.code}: #{res.body.to_s.truncate(300)}")
        return nil
      end
      JSON.parse(res.body)
    rescue StandardError => e
      Rails.logger.warn("[Gemini] #{model} error: #{e.class}: #{e.message}")
      nil
    end

    # Candidates envelope → parsed questions array; anything off-shape is nil.
    def extract(payload, model:)
      if payload.nil?
        Rails.logger.warn("[Gemini] #{model} empty response.")
        return nil
      end
      text = payload.dig("candidates", 0, "content", "parts", 0, "text")
      if text.blank?
        Rails.logger.warn("[Gemini] #{model} no candidates: #{payload.inspect.truncate(300)}")
        return nil
      end
      parsed = JSON.parse(text)
      parsed.is_a?(Hash) ? parsed["questions"] : nil
    rescue JSON::ParserError => e
      Rails.logger.warn("[Gemini] #{model} bad JSON: #{e.message}")
      nil
    end
end
