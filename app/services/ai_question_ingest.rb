# Single gate for every AI pack item, whoever generated it (webhook or Gemini job).
# Same moderation bar as the human form, all-or-nothing per pack: one bad item
# rejects the whole batch so the feed never shows a partial rubric.
class AiQuestionIngest
  Result = Data.define(:questions, :errors, :conflict)

  # One moderation blob shape for the human form and the AI packs alike.
  def self.moderation_text(title:, body:, tags:, reference_answer:, explanation:, options:)
    [ title, body, Array(tags).join(" "), reference_answer, explanation,
      Array(options).map { it.to_h["text"] || it.to_h[:text] }.join(" ") ].join("\n")
  end

  # items: 9 hashes (string/symbol keys): title, body, answer_type,
  # reference_answer, explanation, difficulty, topics, options [{text, correct}].
  # Deadline and author are always server-set; client values are ignored.
  def self.call(items:, batch: AiQuestions.today, source: "webhook")
    batch = batch.to_date
    items = Array(items)
    return Result.new([], [ "AI выключен." ], false) unless AiQuestions.enabled?
    return Result.new([], [ "Нужно #{AiQuestions::PACK_SIZE} вопросов, пришло #{items.size}." ], false) unless items.size == AiQuestions::PACK_SIZE

    questions = []
    errors = []
    Question.transaction do
      # Same-process and cross-process double submits collapse here: the lock key
      # is a stable CRC of the batch date, held to transaction end.
      Question.connection.execute(Question.sanitize_sql([ "SELECT pg_advisory_xact_lock(?)", Zlib.crc32("ai-pack-#{batch}") ]))
      if Question.ai.where(ai_batch: batch).exists?
        errors << "Пакет за #{batch.strftime("%d.%m")} уже создан."
        raise ActiveRecord::Rollback
      end
      author = AiQuestions.bot_user!
      deadline = AiQuestions.deadline_for(batch)
      items.each_with_index do |item, i|
        q = build(item, author:, deadline:, batch:)
        errors.concat(item_errors(q, i)) && next if invalid?(q)
        questions << q
      end
      if errors.empty? && !difficulties_balanced?(questions)
        errors << "Нужно по 3 вопроса каждой сложности (легкое, среднее, сложное)."
      end
      raise ActiveRecord::Rollback if errors.any?
      questions.each(&:save!)
    end
    Result.new(errors.empty? ? questions : [], errors, errors.any? { it.start_with?("Пакет за") })
  end

  private_class_method def self.build(item, author:, deadline:, batch:)
    item = item.to_h.with_indifferent_access
    options = Array(item[:options]).filter_map do |o|
      o = o.to_h.with_indifferent_access
      text = o[:text].to_s.strip
      next if text.empty?
      { "text" => text, "correct" => !!o[:correct] }
    end
    tags = ([ AiQuestions::TAG, item[:difficulty].to_s ] + Array(item[:topics])).map { it.to_s.strip }.reject(&:empty?).uniq
    author.authored_questions.build(
      title: item[:title].to_s.strip, body: item[:body].to_s.strip,
      answer_type: item[:answer_type].to_s.strip.presence || "text",
      reference_answer: item[:reference_answer].to_s.strip,
      explanation: item[:explanation].to_s.strip.presence,
      options:, tags:, deadline:,
      ai_generated: true, ai_batch: batch
    )
  end

  private_class_method def self.invalid?(question)
    return true unless question.valid?
    verdict = ModerationClient.check(text: moderation_text(
      title: question.title, body: question.body, tags: question.tags,
      reference_answer: question.reference_answer, explanation: question.explanation,
      options: question.options))
    if verdict.verdict == :reject
      question.errors.add(:base, "Отклонено проверкой: #{verdict.category}.")
    elsif verdict.verdict == :try_later
      question.errors.add(:base, "Проверка не удалась, попробуйте позже.")
    end
    question.errors.any?
  end

  private_class_method def self.item_errors(question, index)
    question.errors.full_messages.map { "Вопрос #{index + 1}: #{it}" }
  end

  # Rubric rule: exactly a third of the pack per difficulty.
  private_class_method def self.difficulties_balanced?(questions)
    counts = questions.flat_map { it.tags & Question::DIFFICULTIES }.tally
    Question::DIFFICULTIES.all? { counts[it] == AiQuestions::PACK_SIZE / Question::DIFFICULTIES.size }
  end
end
