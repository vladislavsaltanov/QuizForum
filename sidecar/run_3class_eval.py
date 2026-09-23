"""Регрессия портированного пайплайна на ~60 размеченных парах пользователя.

Проверяет два свойства:
1. Совпадение label (positive/partial/false) с разметкой — отчёт + confusion.
2. Инвариант безопасности из кода: тихий авто-false (без needs_review) допустим
   ТОЛЬКО при явном противоречии (legacy contra). Всё остальное обязано уйти в review.

Запуск (нужны скачанные веса, CPU: десятки минут):
  HF_HOME=$PWD/weights/hf-cache sidecar/.venv/bin/python sidecar/run_3class_eval.py [dataset.json]
Выход 1 при нарушениях инварианта; точность только отчитывается (пола нет —
пороги НЕ калибровались на held-out).
"""
import json
import sys

sys.path.insert(0, "sidecar")

from grade import grade_v2, load_grader  # noqa: E402


def load_dataset(path):
    # CLI-скрипт: битый путь — читаемая ошибка в stderr, а не traceback.
    try:
        with open(path, encoding="utf-8") as f:
            dataset = json.load(f)
        return dataset["cases"]
    except (OSError, ValueError, KeyError) as exc:
        print(f"cannot load dataset {path}: {exc}", file=sys.stderr)
        raise SystemExit(2)


def main(path):
    cases = load_dataset(path)
    print(f"cases: {len(cases)}, loading grader...", flush=True)
    print("dtype:", load_grader(), flush=True)

    confusion = {}
    mismatches = []
    silent_false = []
    for c in cases:
        r = grade_v2(c["reference"], c["answer"],
                     "\n".join(c.get("points") or []))
        got, want = r["label"], c["label"]
        confusion[(want, got)] = confusion.get((want, got), 0) + 1
        flag = "OK " if got == want else "MISS"
        print(f"{flag} {c['id']}: want={want} got={got} "
              f"score={r['score']} review={r['needs_review']}", flush=True)
        if got != want:
            mismatches.append((c["id"], want, got, r["review_reasons"]))
        legacy = r.get("legacy", {})
        reason = legacy.get("reason", "")
        contra = (legacy.get("verdict") == "reject"
                  and ("противореч" in reason or reason == "contradiction"))
        if got == "false" and not r["needs_review"] and not contra:
            silent_false.append(c["id"])

    total = len(cases)
    hits = sum(n for (w, g), n in confusion.items() if w == g)
    print(f"\naccuracy: {hits}/{total} = {hits / total:.2f}")
    print("confusion (want->got):")
    for k in sorted(confusion):
        print(f"  {k[0]}->{k[1]}: {confusion[k]}")
    if mismatches:
        print(f"\nmismatches ({len(mismatches)}):")
        for mid, want, got, reasons in mismatches:
            print(f"  {mid}: want={want} got={got} reasons={reasons}")
    if silent_false:
        print(f"\nSILENT-FALSE VIOLATIONS ({len(silent_false)}): {silent_false}")
        return 1
    print("\nno silent-false violations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1] if len(sys.argv) > 1 else "openjev_3class_set2.json"))
