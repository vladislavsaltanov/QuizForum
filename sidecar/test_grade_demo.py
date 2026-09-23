"""Asserts-демо чистых функций grade.py: работает без модели и весов.

Проверяет перенос калибровки 1:1 — инварианты из комментариев кода.
Запуск: sidecar/.venv/bin/python sidecar/test_grade_demo.py
"""
import sys

sys.path.insert(0, "sidecar")

from grade import (
    arbitrate,
    auto_points,
    combine,
    grade_answer,
    legacy_kind,
    normalize_numerals,
    parse_points,
    ramp,
    short_ref_contained,
    split_sentences,
)

# слой 1: короткий эталон + безобидная обвязка принимают без модели
assert short_ref_contained("Канберра.", "Канберра") == "accept"
assert short_ref_contained("Канберра.", "Ответ: Канберра") == "accept"
# лишнее содержательное слово (другой город) — решает модель, не слой 1
assert short_ref_contained("Канберра.", "Канберра, а не Сидней") is None
assert short_ref_contained("Канберра.", "Сидней") is None

# противительные союзы режут предложение: "верное, хотя на самом деле неправда"
sents = split_sentences("Индекс ускоряет поиск, хотя на самом деле замедляет.")
assert len(sents) == 2, sents

# короткий эталон: автомат максимум review, никогда accept
v, _ = combine("Канберра.", {"contradiction": 0.01, "entailment": 0.1, "neutral": 0.8},
                {"contradiction": 0.02, "entailment": 0.9, "neutral": 0.05})
assert v == "review", v
# противоречие в любом направлении блокирует всегда
v, _ = combine("длинный эталон здесь", {"contradiction": 0.9, "entailment": 0.0, "neutral": 0.1},
                {"contradiction": 0.0, "entailment": 0.9, "neutral": 0.1})
assert v == "reject", v

# арбитраж: contra — единственный тихий авто-false
label, score, review, _ = arbitrate("contra", 1)
assert (label, score, review) == ("false", 0.0, False)
# одиночный nosupport — всегда review (ветка ошибается в половине случаев)
label, score, review, _ = arbitrate("nosupport", 1)
assert (label, review) == ("false", True), (label, review)
# review без пунктов — partial с потолком, тоже review
label, score, review, _ = arbitrate("review", 1)
assert (label, score, review) == ("partial", 0.5, True)

# legacy_kind сводит вердикты корректно
assert legacy_kind({"verdict": "accept"}) == "accept"
assert legacy_kind({"verdict": "review"}) == "review"
assert legacy_kind({"verdict": "reject", "reason": "short ref: no support"}) == "nosupport"
assert legacy_kind({"verdict": "reject", "reason": "contradiction"}) == "contra"

# пункты: маркеры -, *, 1. допустимы
assert parse_points("- ускоряет поиск\n* занимает место\n1. замедляет запись") == [
    "ускоряет поиск", "занимает место", "замедляет запись"]
assert auto_points("Канберра.") == ["Канберра"]

# ramp: ниже COV_LO ноль, выше COV_HI единица, между линейно (с плавающей точкой — через допуск)
assert ramp(0.1) == 0.0 and ramp(0.9) == 1.0 and abs(ramp(0.5) - 0.5) < 1e-9

# числительные словами и цифрами — одно и то же, иначе NLI видит противоречие
assert normalize_numerals("двадцать четыре") == "24"
assert normalize_numerals("сто двадцать три") == "123"
assert normalize_numerals("без чисел здесь") == "без чисел здесь"
assert grade_answer("24", "24")["verdict"] == "accept"

print("grade pure functions: all asserts pass")
