u = User.find_or_create_by!(email: "uxone@example.com") { it.name = "Авторыч"; it.password = "ux-pass-1234"; it.password_confirmation = "ux-pass-1234"; it.save! }
u.update!(name: "Авторыч", email_confirmed_at: Time.current)
b = User.find_or_create_by!(email: "uxtwo@example.com") { it.name = "Отвечалыч"; it.password = "ux-pass-1234"; it.password_confirmation = "ux-pass-1234"; it.save! }
b.update!(name: "Отвечалыч", email_confirmed_at: Time.current)
t = u.authored_tests.find_by(title: "UX прогон") || u.authored_tests.create!(title: "UX прогон", deadline: 3.days.from_now, published: true)
q = t.questions.find_by(title: "Сколько ног у паука?") || t.questions.create!(author: u, title: "Сколько ног у паука?", body: "Сосчитайте и ответьте.", answer_type: "text", reference_answer: "8", deadline: t.deadline, points: 5, position: 0)
q2 = t.questions.find_by(title: "Земля вращается?") || t.questions.create!(author: u, title: "Земля вращается?", body: "Выберите верный вариант.", answer_type: "single_choice", reference_answer: "", options: [ { "text" => "Да", "correct" => true }, { "text" => "Нет", "correct" => false } ], deadline: t.deadline, points: 3, position: 1)
Attempt.where(user: b, question: q).first_or_create!(body: "восемь")
pw = u.authored_tests.find_by(title: "Секретный UX") || u.authored_tests.create!(title: "Секретный UX", deadline: 2.days.from_now, published: true, password: "код123")
pw.questions.find_by(title: "Ключ отсюда") || pw.questions.create!(author: u, author: u, title: "Ключ отсюда", body: "Ответ о коде.", answer_type: "text", reference_answer: "x", deadline: pw.deadline, points: 2, position: 0)
dr = u.authored_tests.find_by(title: "Черновик UX") || u.authored_tests.create!(title: "Черновик UX", deadline: 5.days.from_now)
done = u.authored_tests.find_by(title: "Закрытый UX") || u.authored_tests.create!(title: "Закрытый UX", deadline: 1.hour.ago, published: true)
dq = done.questions.find_by(title: "Дважды два") || done.questions.create!(author: u, author: u, title: "Дважды два", body: "число.", answer_type: "text", reference_answer: "4", deadline: done.deadline, points: 10, position: 0)
Attempt.where(user: b, question: dq).first_or_create!(body: "4").update!(verdict: "correct")
puts "seed ok: user=#{u.id} b=#{b.id} open=#{t.id} pw=#{pw.id} draft=#{dr.id} closed=#{done.id}"
