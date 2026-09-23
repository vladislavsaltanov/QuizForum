"""OpenJev 0.8B jury grading: pure pipeline + CPU model loader.

Pure functions ported 1:1 from the calibrated Gradio stand (~60 labeled pairs,
NOT held-out). Thresholds and invariants below are measured, do not retune by hand.
Gradio UI, CUDA and batch API did not carry over. Runs on CPU only:
bfloat16 first, fp32 fallback (some CPU torch builds lack bf16 kernels).
"""
import os
import re
import unicodedata

import torch
from transformers import AutoModelForSequenceClassification, AutoTokenizer

MODEL_ID = "AlexWortega/openjev"
SUBFOLDER = "qwen3.5-0.8b-nli-v2s-long"
# Pin by commit hash, never floating main (supply chain: silent weight swaps).
OPENJEV_REVISION = "552759daad712f1af6c4c13dabcb1e047886fc9c"

MAX_LENGTH = 4096
# Rails caps bodies before sending; this is a second guard so one paste can't OOM CPU.
MAX_INPUT_CHARS = 12000
LONG_INPUT_WARN_TOKENS = 256  # ориентир из описания порта Mimir (обучение на 256), для v2 не подтверждено

# Порядок меток из model card: 0=contradiction, 1=entailment, 2=neutral
LABELS = ["contradiction", "entailment", "neutral"]

# ============================================================================
# ЛОГИКА РЕШЕНИЯ (чистый Python, проверена тестами на реальных числах пользователя)
# Пороги подобраны на ~60 размеченных парах и НЕ откалиброваны на отложенной выборке.
# ============================================================================

TH_CONTRA_BLOCK = 0.5
TH_E_MIN = 0.6
TH_E_MAX = 0.8
TH_E_REVIEW_MIN = 0.3
TH_E_COVER = 0.75       # bwd.E: ответ покрывает эталон (главный разделитель - fwd.E >= 0.2)
TH_E_COVER_FWD_MIN = 0.2  # fwd.E: нижняя граница для этого профиля
TH_SENT_CONTRA = 0.8
SHORT_REF_TOKENS_CHARS = 25
SHORT_REF_CHARS = 40  # граница 'короткого' эталона для combine()

GRADER_DTYPE = None
_tokenizer = None
_model = None
NLI_TEMPLATE = None


def load_grader(force_fp32=None):
    """Loads tokenizer + model on CPU. Returns dtype actually used ('bfloat16'/'fp32')."""
    global _tokenizer, _model, NLI_TEMPLATE, GRADER_DTYPE
    if _model is not None:
        return GRADER_DTYPE
    if force_fp32 is None:
        force_fp32 = os.environ.get("OPENJEV_FORCE_FP32") == "1"
    dtypes = [torch.float32] if force_fp32 else [torch.bfloat16, torch.float32]
    last_exc = None
    for dt in dtypes:
        try:
            _tokenizer = AutoTokenizer.from_pretrained(
                MODEL_ID, subfolder=SUBFOLDER, revision=OPENJEV_REVISION)
            _model = AutoModelForSequenceClassification.from_pretrained(
                MODEL_ID, subfolder=SUBFOLDER, revision=OPENJEV_REVISION,
                dtype=dt).to("cpu")
            _model.eval()
            NLI_TEMPLATE = _model.config.nli_template
            GRADER_DTYPE = "bfloat16" if dt == torch.bfloat16 else "fp32"
            return GRADER_DTYPE
        except Exception as exc:  # bf16 missing on this CPU -> fall through to fp32
            last_exc = exc
            _tokenizer, _model = None, None
    raise RuntimeError(f"openjev load failed (bf16+fp32): {last_exc}")


def normalize(s):
    s = unicodedata.normalize("NFKC", s).lower()
    s = re.sub(r"[^\w\s]", " ", s, flags=re.UNICODE)
    return re.sub(r"\s+", " ", s).strip()

ADVERSATIVE = re.compile(
    r"(?:,\s*|\s+)(?=(?:хотя|но|однако|зато|while|but|although|however)\b)",
    flags=re.IGNORECASE,
)

def split_sentences(text):
    parts = re.split(r"(?<=[.!?…])\s+|\n+", text.strip())
    out = []
    for p in parts:
        # дополнительно режем по противительным союзам: "верное, хотя на самом деле неправда"
        for q in ADVERSATIVE.split(p):
            q = q.strip(" ,;")
            if q and len(re.sub(r"\W", "", q)) >= 2:
                out.append(q)
    return out

def combine(reference, fwd, bwd):
    """
    Короткий эталон: fwd (эталон -> ответ) структурно занижен, потому что более длинный ответ
    не может быть 'следствием' короткого эталона. Главным считается bwd (ответ -> эталон).
    Длинный эталон: следование нужно в обоих направлениях (min).
    Противоречие в любом направлении блокирует всегда.
    """
    c_max = max(fwd["contradiction"], bwd["contradiction"])
    if c_max >= TH_CONTRA_BLOCK:
        return "reject", "contradiction"

    e_f, e_b = fwd["entailment"], bwd["entailment"]

    if len(reference.strip()) <= SHORT_REF_CHARS:
        # ВАЖНО: для короткого эталона NLI не различает "безобидную добавку" и "противоречащую":
        # fwd.contradiction у обоих классов < 0.05, bwd.E у обоих 0.80-0.96 (измерено на 7 мягких атаках).
        # Поэтому автоматический accept здесь невозможен, максимум review.
        # Автоприём для коротких эталонов остаётся только в слое 1 (эталон + белый список обвязки).
        if e_b >= 0.55 and c_max < 0.3:
            return "review", "short ref: entails reference, but extra content cannot be verified"
        return "reject", "short ref: no support"

    e_min, e_max = min(e_f, e_b), max(e_f, e_b)
    if e_min >= TH_E_MIN and e_max >= TH_E_MAX:
        return "accept", "both directions"
    if e_max >= TH_E_MAX and e_min >= TH_E_REVIEW_MIN:
        return "review", "one direction weak"
    # Профиль "ответ полностью покрывает эталон и добавляет лишнее": bwd очень высокий, fwd низкий.
    # Верный ответ с уточнением ("... но не MD5") и мягкая атака выглядят одинаково по fwd,
    # поэтому только review. Разделяет классы fwd.E (верные 0.21-0.43, атаки 0.002-0.048), bwd.E лишь страховка.
    if e_b >= TH_E_COVER and e_f >= TH_E_COVER_FWD_MIN and c_max < 0.3:
        return "review", "answer covers reference, extra content unverified"
    return "reject", "no support"


def short_ref_contained(reference, answer):
    """
    Для КОРОТКОГО эталона (<= SHORT_REF_TOKENS_CHARS символов): принять, только если
    ответ состоит из эталона плюс безобидная обвязка. Любое "лишнее содержательное" слово
    (другой город, число, отрицание) => None, решает модель.
    Белый список сознательно короткий: лучше отправить на модель, чем ошибочно принять.
    """
    r, a = normalize(reference), normalize(answer)
    if not r or not a or len(r) > SHORT_REF_TOKENS_CHARS:
        return None
    if a == r:
        return "accept"
    r_words, a_words = r.split(), a.split()
    n = len(r_words)
    if not any(a_words[i:i+n] == r_words for i in range(len(a_words) - n + 1)):
        return None
    FILLER = {"это", "ответ", "правильный", "верный", "верно", "будет", "получится",
              "вернёт", "вернет", "равно", "равна", "равен", "как", "то", "есть", "так",
              "the", "answer", "is", "it", "its", "correct", "right"}
    rest = [w for w in a_words if w not in set(r_words)]
    # слова из обвязки допустимы, всё остальное - нет
    if any(w not in FILLER for w in rest):
        return None
    # повторы эталона допустимы только в небольшом числе
    if a_words.count(r_words[0]) > 2:
        return None
    return "accept"



# ============================================================================
# V2: ТРЁХКЛАССНАЯ ОЦЕНКА (positive / partial / false) И ОЧЕРЕДЬ REVIEW
#
# Идея: две независимые оси. Корректность (нет противоречий) решает измеренный конвейер выше.
# Полнота (сколько пунктов эталона покрыто ответом) - новый сигнал: NLI на уровне пунктов.
# ВСЁ, что касается покрытия пунктов, НЕ измерено на реальной модели: пороги ниже стартовые,
# их нужно откалибровать скриптом run_3class_eval.py. Пока TRUST_COVERAGE = False, любой
# частичный балл и любое решение, зависящее только от покрытия, уходит автору в review.
# ============================================================================
TRUST_COVERAGE = False   # включать только после калибровки (см. run_3class_eval.py)
COV_LO = 0.30            # E(ответ -> пункт) ниже: пункт не покрыт
COV_HI = 0.70            # E выше: пункт покрыт полностью; между порогами линейно
T_POSITIVE = 0.85        # доля покрытых пунктов >= : positive
T_PARTIAL = 0.25         # >= : partial, иначе баллов нет
BORDER = 0.08            # близость к порогу, при которой решение уходит в review
REVIEW_SCORE_CAP = 0.5   # временный потолок балла для ответов в очереди review
MAX_POINTS = 8
MAX_SEGMENTS = 8

CONJ_SPLIT = re.compile(r",\s+(?:и|а|но|причём|а также)\s+|\s+а также\s+", re.IGNORECASE)


def parse_points(text):
    """Пункты от автора: по одному на строку, маркеры '-', '*', '1.' допустимы."""
    out = []
    for ln in (text or "").splitlines():
        ln = re.sub(r"^\s*(?:[-*\u2022]|\d+[.)])\s+", "", ln).strip()
        if ln:
            out.append(ln)
    return out[:MAX_POINTS]


def _split_long(piece, max_len=70, min_part=20):
    piece = piece.strip(" ,;")
    if len(piece) <= max_len:
        return [piece]
    mid = len(piece) / 2

    def valid(s, e):
        return s >= min_part and len(piece) - e >= min_part

    conj = [(m.start(), m.end()) for m in CONJ_SPLIT.finditer(piece) if valid(m.start(), m.end())]
    comma = [(m.start(), m.end()) for m in re.finditer(r",\s+", piece) if valid(m.start(), m.end())]
    cands = conj or comma
    if not cands:
        return [piece]
    s, e = min(cands, key=lambda se: abs(se[0] - mid))
    return _split_long(piece[:s]) + _split_long(piece[e:])


def auto_points(reference):
    """Эвристический разбор эталона на пункты. Ненадёжен: лучше, чтобы автор задавал пункты сам."""
    text = reference.strip()
    parts = re.split(r"(?<=[.!?\u2026])\s+|\s*;\s*|\n+", text)
    points = []
    for part in parts:
        for p in _split_long(part):
            p = p.strip(" ,;.")
            if len(re.sub(r"\W", "", p)) >= 8:
                points.append(p)
    points = points[:MAX_POINTS]
    return points if points else [text.strip(" .")]


def ramp(e):
    if e <= COV_LO:
        return 0.0
    if e >= COV_HI:
        return 1.0
    return (e - COV_LO) / (COV_HI - COV_LO)


def _label_from_score(score):
    if score >= T_POSITIVE:
        return "positive"
    if score >= T_PARTIAL:
        return "partial"
    return "none"


def _round_score(x):
    return round(x * 20) / 20


def legacy_kind(r):
    """Сводит вердикт измеренного конвейера к одному из: accept | review | nosupport | contra."""
    v, why = r["verdict"], r.get("reason", "")
    if v == "accept":
        return "accept"
    if v == "review":
        return "review"
    if "no support" in why:
        return "nosupport"
    return "contra"   # contradiction, "предложение N противоречит...", "ответ пустой..."


def arbitrate(kind, n_points, cov_score=None, fwd_e=None, points_source="single"):
    """
    Итоговое решение. Возвращает (label, score, needs_review, reasons).

    Правила безопасности (36720 комбинаций-инвариантов + регрессия на 60 размеченных РЕАЛЬНЫХ
    прогонах через Space, 2026-09; см. переписку с датасетом openjev_3class_set2.json):
      - kind == "contra" - единственный сигнал, достаточно надёжный для авто-false без review
        (0 ложных срабатываний на сотнях измеренных атак за весь проект);
      - kind == "accept" c полным покрытием (или без пунктов) - единственный путь к авто-positive;
      - НИЗКОЕ покрытие (cov_label == "false") больше НЕ даёт авто-false: на реальном прогоне
        coverage_score == 0 восемь раз из восьми оказался лексической слепотой к перифразу
        (напр. "сбрасывать при изменении данных" не был признан как "требует инвалидации"),
        а не отсутствием ответа - сигнал недостаточно надёжен для решения без человека;
      - kind == "nosupport" без независимого покрытия (одиночный факт, <2 пунктов) тоже больше
        не даёт авто-false: на той же выборке 2 из 4 таких случаев (HTTPS, Docker-контейнер)
        были верными ответами, ошибочно отклонёнными - ветка ошибается слишком часто (50%)
        для автовердикта. Раньше здесь была развилка по fwd_e >= 0.6 - убрана как ненадёжная.
      - при TRUST_COVERAGE=False любой partial уходит в review.
    """
    if kind == "contra":
        return "false", 0.0, False, ["ответ противоречит эталону"]

    # нет независимого сигнала покрытия (одиночный факт): решает только измеренный конвейер
    if n_points < 2 or cov_score is None:
        if kind == "accept":
            return "positive", 1.0, False, []
        if kind == "review":
            return "partial", REVIEW_SCORE_CAP, True, [
                "ответ содержит непроверяемое дополнение или слабо подтверждён эталоном"]
        # kind == "nosupport": ветка ошибается в половине измеренных случаев - никогда не гасим тихо
        return "false", 0.0, True, [
            "ответ не подтверждён эталоном; без пунктов и без явного противоречия решение ненадёжно"]

    cov_label = _label_from_score(cov_score)
    border = any(abs(cov_score - t) < BORDER for t in (T_POSITIVE, T_PARTIAL))
    part_score = _round_score(cov_score)

    if cov_label == "positive":
        # border здесь не нужен: kind == "accept" - независимое подтверждение целиком, а полное
        # покрытие - второе независимое подтверждение; двух согласных сигналов достаточно
        needs_review = (kind != "accept")
        reasons = [] if kind == "accept" else [
            "все заданные пункты покрыты, но целиком ответ NLI подтвердил слабо"]
        return "positive", 1.0, needs_review, reasons

    if cov_label == "partial":
        uncertain = (not TRUST_COVERAGE) or border or points_source == "auto"
        return "partial", part_score, uncertain, ["покрыта часть пунктов"]

    # низкое покрытие: ВСЕГДА review, независимо от TRUST_COVERAGE - подтверждено 8 реальными
    # ложными cov=0 на верных по сути ответах (лексический перифраз, не распознанный NLI)
    return "false", 0.0, True, [
        "пункты не покрыты по формальному совпадению — возможен незамеченный перифраз, нужна проверка"]


def _require_loaded():
    # _classify is the only reader of the globals; fail loud if boot skipped the loader.
    if _model is None or _tokenizer is None or NLI_TEMPLATE is None:
        raise RuntimeError("grader used before load_grader()")


def _classify(pairs):
    """Батч-инференс. Возвращает (список [c, e, n], список длин в токенах до усечения)."""
    _require_loaded()
    if _tokenizer is None or _model is None or NLI_TEMPLATE is None:
        raise RuntimeError("grader used before load_grader()")
    texts = [NLI_TEMPLATE.format(premise=p, hypothesis=h) for p, h in pairs]
    untruncated = _tokenizer(texts, truncation=False)["input_ids"]
    token_counts = [len(ids) for ids in untruncated]

    enc = _tokenizer(
        texts,
        return_tensors="pt",
        truncation=True,
        max_length=MAX_LENGTH,
        padding=True,
    )

    with torch.inference_mode():
        logits = _model(**enc).logits
        probs = torch.softmax(logits.float(), dim=-1).cpu().tolist()
    return probs, token_counts


def _as_dict(p):
    return {"contradiction": p[0], "entailment": p[1], "neutral": p[2]}


def _round(d):
    return {k: round(v, 4) for k, v in d.items()}


def grade_answer(reference, answer):
    """
    Полный конвейер оценки одного ответа. Возвращает словарь с итогом и всеми промежуточными числами.

    Слои:
      0. Пустой/слишком короткий ввод - reject без модели.
      1. Короткий эталон + безобидная обвязка - accept без модели.
      2. Декомпозиция ответа на предложения: любое предложение с сильным contradiction
         (в любом направлении) блокирует ответ. Закрывает "верное начало + опровержение".
      3. Целый ответ в обоих направлениях, правило combine() (min по entailment).
    """
    reference, answer = reference.strip(), answer.strip()

    # --- слой 0 ---
    if len(re.sub(r"\W", "", answer)) < 2:
        return {"verdict": "reject", "reason": "ответ пустой или из одного символа",
                "trace": ["слой 0: отклонён без модели"]}

    # --- слой 1 ---
    if short_ref_contained(reference, answer) == "accept":
        return {"verdict": "accept", "reason": "короткий эталон, ответ = эталон + безобидная обвязка",
                "trace": ["слой 1: принято без модели"]}

    # --- слои 2 и 3: собираем ВСЕ пары в один батч ---
    sentences = split_sentences(answer)
    pairs, tags = [], []
    # целый ответ, оба направления
    pairs.append((reference, answer))
    tags.append(("whole", "fwd", None))
    pairs.append((answer, reference))
    tags.append(("whole", "bwd", None))
    # предложения ответа (только если их больше одного)
    if len(sentences) > 1:
        for i, s in enumerate(sentences):
            pairs.append((reference, s))
            tags.append(("sent", "fwd", i))
            pairs.append((s, reference))
            tags.append(("sent", "bwd", i))

    probs, counts = _classify(pairs)

    whole = {}
    sent_info = {}
    max_tokens = 0
    for (kind, direction, idx), pr, tc in zip(tags, probs, counts, strict=True):
        max_tokens = max(max_tokens, tc)
        d = _as_dict(pr)
        if kind == "whole":
            whole[direction] = d
        else:
            sent_info.setdefault(idx, {})[direction] = d

    notes = []
    if max_tokens > MAX_LENGTH:
        notes.append(f"УСЕЧЕНО: {max_tokens} токенов > {MAX_LENGTH}, вердикт ненадёжен")
    elif max_tokens > LONG_INPUT_WARN_TOKENS:
        notes.append(f"длинный вход ({max_tokens} токенов): вне обучающей длины ~{LONG_INPUT_WARN_TOKENS}")

    # --- слой 2: сильное противоречие в отдельном предложении ---
    # В направлении ref->user (fwd) предложение ответа как hypothesis: если оно противоречит эталону,
    # это утверждение, которое эталон опровергает. Именно этот сигнал ловит "верное начало + опровержение".
    for idx, dirs in sent_info.items():
        c_fwd = dirs["fwd"]["contradiction"]
        if c_fwd >= TH_SENT_CONTRA:
            return {
                "verdict": "reject",
                "reason": f"предложение {idx + 1} противоречит эталону",
                "sentence": sentences[idx],
                "contradiction_fwd": round(c_fwd, 4),
                "whole_fwd": _round(whole["fwd"]),
                "whole_bwd": _round(whole["bwd"]),
                "trace": ["слой 2: блок по предложению"],
                "notes": notes,
            }

    # --- слой 3 ---
    verdict, why = combine(reference, whole["fwd"], whole["bwd"])
    return {
        "verdict": verdict,
        "reason": why,
        "whole_fwd": _round(whole["fwd"]),
        "whole_bwd": _round(whole["bwd"]),
        "sentences_checked": len(sentences) if len(sentences) > 1 else 0,
        "trace": ["слой 3: combine() по обоим направлениям"],
        "notes": notes,
    }


def _coverage(answer, points):
    """NLI на уровне пунктов: E(ответ или его предложение -> пункт). Берём лучший сегмент на пункт."""
    sents = split_sentences(answer)
    segs = [answer] + (sents[:MAX_SEGMENTS] if len(sents) > 1 else [])
    pairs, idx = [], []
    for i, p in enumerate(points):
        for j, s in enumerate(segs):
            pairs.append((s, p))
            idx.append((i, j))
    probs, counts = _classify(pairs)

    best = [{"entailment": 0.0, "contradiction": 0.0, "segment": 0} for _ in points]
    for (i, j), pr in zip(idx, probs, strict=True):
        if pr[1] >= best[i]["entailment"]:
            best[i] = {"entailment": pr[1], "contradiction": pr[0], "segment": j}

    details = []
    for p, b in zip(points, best, strict=True):
        cov = ramp(b["entailment"])
        details.append({
            "point": p,
            "coverage": round(cov, 3),
            "entailment": round(b["entailment"], 4),
            "contradiction": round(b["contradiction"], 4),
            "evidence": segs[b["segment"]][:80] if b["entailment"] >= COV_LO else None,
            "covered": cov >= 0.5,
        })
    score = sum(ramp(b["entailment"]) for b in best) / len(best)
    return {"score": score, "details": details, "max_tokens": max(counts) if counts else 0}


def _truncate(text, notes):
    # Одна вставка не должна съесть CPU-память: режем до лимита, фиксируем в notes.
    if len(text) > MAX_INPUT_CHARS:
        notes.append(f"вход обрезан до {MAX_INPUT_CHARS} символов")
        return text[:MAX_INPUT_CHARS]
    return text


def grade_v2(reference, answer, points_text=""):
    """
    Итог для QuizForum: label (positive/partial/false), score 0..1, needs_review, причины, разбор по пунктам.
    Измеренный конвейер grade_answer() остаётся нетронутым и работает как первый судья.
    """
    reference, answer = reference.strip(), answer.strip()
    pre_notes = []
    reference = _truncate(reference, pre_notes)
    answer = _truncate(answer, pre_notes)
    author = parse_points(points_text)
    if author:
        points, source = author, ("author" if len(author) > 1 else "single")
    else:
        points = auto_points(reference)
        source = "auto" if len(points) > 1 else "single"

    legacy = grade_answer(reference, answer)
    kind = legacy_kind(legacy)
    layer1 = legacy.get("reason", "").startswith("короткий эталон")
    fwd_e = (legacy.get("whole_fwd") or {}).get("entailment")
    notes = list(pre_notes) + list(legacy.get("notes", []))

    cov = None
    if len(points) >= 2 and kind in ("accept", "review", "nosupport") and not layer1:
        cov = _coverage(answer, points)
        if cov["max_tokens"] > MAX_LENGTH:
            notes.append(f"УСЕЧЕНО при оценке пунктов: {cov['max_tokens']} токенов")

    label, score, needs_review, reasons = arbitrate(
        kind, len(points), cov["score"] if cov else None, fwd_e, source)

    return {
        "label": label,
        "score": score,
        "needs_review": needs_review,
        "review_reasons": reasons,
        "points_source": source,
        "coverage_score": round(cov["score"], 3) if cov else None,
        "points": cov["details"] if cov else [{"point": p} for p in points],
        "missing_points": [d["point"] for d in cov["details"] if not d["covered"]] if cov else [],
        "legacy": {k: legacy.get(k) for k in ("verdict", "reason", "whole_fwd", "whole_bwd") if k in legacy},
        "notes": notes,
    }
