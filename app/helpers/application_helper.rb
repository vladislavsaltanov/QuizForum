# View helpers: verdict labels, avatars, Russian time phrases.
module ApplicationHelper
  VERDICT_LABELS = {
    "pending" => "На проверке",
    "correct" => "Правильно",
    "partial" => "Почти, но нет",
    "incorrect" => "Неправильно"
  }.freeze

  # Human-readable verdict name.
  def verdict_label(verdict)
    VERDICT_LABELS.fetch(verdict.to_s, verdict.to_s)
  end

  # CSS hook for verdict badges.
  def verdict_class(verdict)
    "qf-verdict-#{verdict}"
  end

  # Two-letter avatar initials.
  def initials(name)
    name.to_s.split.first(2).map(&:first).join.upcase
  end

  # Russian countdown to the deadline; rails-i18n would be a new dep for one line.
  def time_left(deadline)
    secs = (deadline - Time.current).to_i
    return "завершён" if secs <= 0
    mins = secs / 60
    return "меньше минуты" if mins < 1
    return plural_ru(mins, "минута", "минуты", "минут") if secs < 3600
    return plural_ru(secs / 3600, "час", "часа", "часов") if secs < 86400
    plural_ru(secs / 86400, "день", "дня", "дней")
  end

  # Russian relative timestamp.
  def ago_ru(time)
    secs = (Time.current - time).to_i
    return "только что" if secs < 60
    return "#{plural_ru(secs / 60, 'минута', 'минуты', 'минут')} назад" if secs < 3600
    return "#{plural_ru(secs / 3600, 'час', 'часа', 'часов')} назад" if secs < 86400
    return "#{plural_ru(secs / 86400, 'день', 'дня', 'дней')} назад" if secs < 7 * 86400
    time.strftime("%d.%m %H:%M")
  end

  private
    # Russian plural form picker.
    def plural_ru(n, one, few, many)
      m10 = n % 10
      m100 = n % 100
      form = if m10 == 1 && m100 != 11
        one
      elsif (2..4).include?(m10) && !(12..14).include?(m100)
        few
      else
        many
      end
      "#{n} #{form}"
    end
end
