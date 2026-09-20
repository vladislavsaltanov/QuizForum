# Demo bank for development. Idempotent: safe to re-run.
ivan = User.find_or_create_by!(email: "ivan@example.com") do |u|
  u.name = "Иванов Иван Иванович"
  u.display_role = "доцент кафедры"
  u.password = "password12345678"
  u.password_confirmation = "password12345678"
end
anna = User.find_or_create_by!(email: "anna@example.com") do |u|
  u.name = "Петрова Анна Сергеевна"
  u.display_role = "старший преподаватель"
  u.password = "password12345678"
  u.password_confirmation = "password12345678"
end
oleg = User.find_or_create_by!(email: "oleg@example.com") do |u|
  u.name = "Сидоров Олег Павлович"
  u.password = "password12345678"
  u.password_confirmation = "password12345678"
end

questions = [
  { title: "Напишите алгоритм поиска подстроки",
    body: "Опишите алгоритм поиска подстроки в строке за линейное время. Разберите префикс-функцию на примере.",
    answer_type: "text", reference_answer: "Алгоритм Кнута — Морриса — Пратта: префикс-функция …",
    deadline: 7.days.from_now, author: ivan, tags: %w[программирование среднее алгоритмы] },
  { title: "Докажите сходимость метода простых итераций",
    body: "Сформулируйте достаточное условие сходимости и докажите его.",
    answer_type: "text", reference_answer: "Сжимающее отображение: q < 1 …",
    deadline: 30.days.ago, author: anna, tags: %w[математика сложное анализ] },
  { title: "Что выведет этот фрагмент на Python?",
    body: "print([i * 2 for i in range(3)])",
    answer_type: "single_choice",
    options: [ { "text" => "[0, 2, 4]", "correct" => true }, { "text" => "[1, 2, 3]", "correct" => false }, { "text" => "[0, 1, 2]", "correct" => false } ],
    reference_answer: "[0, 2, 4] — range(3) даёт 0, 1, 2.",
    deadline: 30.days.ago, author: oleg, tags: %w[программирование легкое python] },
  { title: "Объясните разницу между TCP и UDP",
    body: "Когда какой протокол уместен? Приведите по примеру.",
    answer_type: "multiple_choice",
    options: [ { "text" => "TCP гарантирует доставку и порядок", "correct" => true }, { "text" => "UDP быстрее за счёт отсутствия handshake", "correct" => true }, { "text" => "UDP гарантирует порядок пакетов", "correct" => false } ],
    reference_answer: "TCP — надёжный поток, UDP — дейтаграммы без гарантий.",
    deadline: 30.days.ago, author: ivan, tags: %w[сети среднее протоколы] },
  { title: "Найдите предел последовательности",
    body: "a(n) = (1 + 1/n)^n. Чему равен предел при n → ∞?",
    answer_type: "code",
    reference_answer: "e — второй замечательный предел. Численно: math.e.",
    deadline: 7.days.from_now, author: anna, tags: %w[математика среднее анализ] },
  { title: "Что вернёт typeof null в JavaScript?",
    body: "Выберите один верный вариант.",
    answer_type: "single_choice",
    options: [ { "text" => "object", "correct" => true }, { "text" => "null", "correct" => false }, { "text" => "undefined", "correct" => false } ],
    reference_answer: "object — известный баг языка.",
    deadline: 7.days.from_now, author: oleg, tags: %w[программирование легкое javascript] },
  { title: "Какие утверждения о Git верны?",
    body: "Отметьте все верные варианты.",
    answer_type: "multiple_choice",
    options: [ { "text" => "commit фиксирует снимок", "correct" => true }, { "text" => "push отправляет в удалённый репозиторий", "correct" => true }, { "text" => "branch удаляет историю", "correct" => false } ],
    reference_answer: "Верны первые два.",
    deadline: 7.days.from_now, author: ivan, tags: %w[программирование среднее git] }
]

questions.each do |attrs|
  Question.find_or_create_by!(title: attrs[:title]) do |q|
    q.assign_attributes(attrs)
  end
end

# Demo attempts for stats on the closed Python question.
python_q = Question.find_by!(title: "Что выведет этот фрагмент на Python?")
[ [ oleg, [ "0" ], "correct" ], [ anna, [ "1" ], "incorrect" ], [ ivan, [ "0", "2" ], "correct" ] ].each do |user, picked, _|
  Attempt.find_or_create_by!(question: python_q, user: user) do |a|
    a.selected = picked
  end
end
Comment.find_or_create_by!(question: python_q, user: anna, body: "А будет ли это работать на Python 2?") do |c|
  c.status = "approved"
end
