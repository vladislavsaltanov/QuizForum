"""Deterministic input generation, per-language drivers, output comparison.

Single implementation of the input generator lives here; Rails only sends a
seed and a case count. User code never runs in this process — only in a
per-case subprocess with a timeout, a stdout cap, an empty stdin and a
secret-free env. Real containment (non-root, no net, tmpfs, cgroups) comes
from the Docker image.
"""
import ast
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import textwrap

LANGUAGES = ("python", "javascript", "typescript", "ruby", "go", "java", "c++", "c#")
STDOUT_CAP = 65536
SAFE_MAX = 2 ** 53 - 1  # cross-language integer safety bound (spec review focus)

# Mtime of this file, exposed via /up so stale processes are visible.
SOURCE_MTIME = int(os.path.getmtime(__file__))


def _version(cmd):
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=10, text=True)
        lines = ((proc.stdout or "") + "\n" + (proc.stderr or "")).strip().splitlines()
        return lines[0].strip() if lines else "unknown"
    except Exception:
        return "missing"


RUNTIMES = {
    "python": _version([sys.executable, "--version"]),
    "node": _version(["node", "--version"]),
    "go": _version(["go", "--version"]),
    "g++": _version(["g++", "--version"]),
    "java": _version(["java", "--version"]),
    "dotnet": _version(["dotnet", "--version"]),
    "ruby": _version(["ruby", "--version"]),
}

# Drivers are appended to the user program. They read one JSON arg-list from
# argv, call solve(*args) and emit exactly one OUT:<json> line. Anything else
# on stdout (user prints) is ignored by the parser but counts toward the cap.
# No solve / wrong arity / exception / bad output value => nonzero exit or no
# OUT line => the case fails (attempt) or the input is dropped (reference).
_PY_DRIVER = """
import json as __dr_json, sys as __dr_sys
import inspect as __dr_inspect, asyncio as __dr_asyncio
try:
    __dr_args = __dr_json.loads(__dr_sys.argv[1])
except Exception:
    __dr_sys.exit(2)
try:
    __dr_fn = solve
except NameError:
    print("ERR:NameError: solve is not defined", file=__dr_sys.stderr)
    __dr_sys.exit(3)
try:
    __dr_out = __dr_fn(*__dr_args)
    if __dr_inspect.isawaitable(__dr_out):
        __dr_out = __dr_asyncio.run(__dr_out)
    __dr_sys.stdout.write("OUT:" + __dr_json.dumps(__dr_out, allow_nan=False))
except SystemExit:
    raise
except BaseException as __dr_e:
    print("ERR:%s: %s" % (type(__dr_e).__name__, __dr_e), file=__dr_sys.stderr)
    __dr_sys.exit(1)
"""

_JS_DRIVER = """
(async () => {
const __dr_args = JSON.parse(process.argv[2]);
let __dr_out;
try { __dr_out = await solve(...__dr_args); }
catch (__dr_e) { process.stderr.write("ERR:" + ((__dr_e && __dr_e.name) || "Error")); process.exit(1); }
if (__dr_out === undefined) __dr_out = null;
process.stdout.write("OUT:" + JSON.stringify(__dr_out));
})();
"""

_RB_DRIVER = """
require "json"
begin
  __dr_args = JSON.parse(ARGV[0])
  __dr_out = solve(*__dr_args)
  STDOUT.write("OUT:" + JSON.generate(__dr_out))
rescue SystemExit
  raise
rescue Exception => __dr_e
  STDERR.write("ERR:#{__dr_e.class}: #{__dr_e.message}\n")
  exit(1)
end
"""

DRIVERS = {"python": _PY_DRIVER, "javascript": _JS_DRIVER,
    # TypeScript runs on the JS runtime via node strip-types; the driver
    # itself is plain JS, so no type syntax ever reaches the stripper.
    "typescript": _JS_DRIVER, "ruby": _RB_DRIVER}
# Resolve interpreters once, with the startup PATH: ad-hoc toolchains
# (fnm/rbenv shims) live outside /usr/bin. Spawn env carries PATH only —
# no secrets — so shims keep working and no system-ruby fallback sneaks in.
SPAWN_ENV = {"PATH": os.environ.get("PATH", "/usr/bin:/bin:/usr/local/bin")}


def _interp(name, argv0):
    if argv0 is not None:
        return [argv0]
    found = shutil.which(name, path=SPAWN_ENV["PATH"])
    return [found] if found else None


INTERPS = {"python": [sys.executable],
           "javascript": _interp("node", None),
           "typescript": _interp("node", None),
           "ruby": _interp("ruby", None),
           "go": _interp("go", None),
           "java": _interp("java", None),
           "c++": _interp("g++", None),
           "c#": _interp("dotnet", None)}
EXTS = {"python": "py", "javascript": "js", "typescript": "ts", "ruby": "rb"}

# Languages needing ahead-of-time compilation (binary runs directly).
COMPILED = ("go", "java", "c++", "c#")
CPP_BUILD_TIMEOUT = 60
CPP_TYPES = {"int", "long", "double", "string", "bool",
             "vector<int>", "vector<long>", "vector<double>",
             "vector<string>", "vector<bool>"}
GO_BUILD_TIMEOUT = 60
GO_TYPES = {"int", "int64", "float64", "string", "bool",
            "[]int", "[]string", "[]float64", "[]bool"}
JAVA_BUILD_TIMEOUT = 60
JAVA_TYPES = {"int", "long", "double", "String", "boolean",
              "int[]", "long[]", "double[]", "String[]", "boolean[]"}


class BuildError(RuntimeError):
    """Source or harness unusable (reference) or uncompilable (attempt)."""


class HarnessError(BuildError):
    """No usable harness at all (e.g. cross-language compiled attempt)."""
    # Unlike a compile failure (broken code -> incorrect), this means the
    # check could not run: the caller must report needs_review, not a verdict.



def write_program(tmpdir, stem, language, code):
    """Write user code + driver sentinel to a file; return its path."""
    if language == "python":
        code = textwrap.dedent(code)
    path = os.path.join(tmpdir, "%s.%s" % (stem, EXTS[language]))  # noqa: path stem is server-chosen ('ref'/'att'), never user input
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(code)
            if not code.endswith("\n"):
                handle.write("\n")
            handle.write(DRIVERS[language])
    except OSError as exc:
        # Callers treat this as runner failure: 500, job retries, stays pending.
        raise RuntimeError(f"cannot write program file: {exc}") from exc
    return path


def _strip_go_package(code):
    """Drop a leading `package x` line; pasted full programs stay buildable."""
    out = []
    for line in code.splitlines(keepends=True):
        if len(line.split()) == 2 and line.split()[0] == "package":
            continue
        out.append(line)
    return "".join(out)


def go_signature(code):
    """Param types of `func solve`, or None when unusable or unsupported."""
    match = re.search("func +solve *[(]([^)]*)[)]([^{]*)", code)
    if not match:
        return None
    raw_params = match.group(1)
    raw_ret = match.group(2).split(chr(10))[0].strip()
    if "..." in raw_params:
        return None  # variadic: uncountable, caller reviews
    types = []
    for part in _split_top_level(raw_params):
        part = part.strip()
        if not part:
            continue
        if part.startswith("{") or part.startswith("["):
            return None
        tok = part.split()[-1]
        if tok not in GO_TYPES:
            return None
        types.append(tok)
    if raw_ret.startswith("("):
        if not raw_ret.endswith(")"):
            return None
        inner = raw_ret[1:-1].strip()
        if "," in inner:
            return None  # multiple results: unsupported
        ret = inner.split()[-1] if inner.split() else ""
    else:
        ret = raw_ret.split()[-1] if raw_ret.split() else ""
    if ret not in GO_TYPES:
        return None
    return types


def _strip_c_comments(code):
    """Remove // and /* */ comments; string/char literals blanked, not dropped."""
    token = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'|/\*.*?\*/|//[^\n]*', re.DOTALL)

    def _drop(match):
        tok = match.group(0)
        if tok.startswith("/"):
            return ""
        return '""'
    return token.sub(_drop, code)


def _balanced_params(clean, open_index):
    """(inside, close_index) of the paren group opening at open_index."""
    depth, i = 0, open_index
    while i < len(clean):
        if clean[i] == "(":
            depth += 1
        elif clean[i] == ")":
            depth -= 1
            if depth == 0:
                return clean[open_index + 1:i], i
        i += 1
    return None, -1


def _java_param_type(part):
    """One `Type name` declaration -> type in JAVA_TYPES, or None."""
    part = part.strip()
    match = re.match(r"^(.*?)\s*([A-Za-z_$][\w$]*)$", part)
    if not match:
        return None
    typ = re.sub(r"@\w+(\([^()]*\))?", "", match.group(1))
    typ = " ".join(tok for tok in typ.split() if tok != "final")
    typ = typ.replace(" ", "")
    return typ if typ in JAVA_TYPES else None


def java_signature(code):
    """Param types of `static solve` in class Solution, or None."""
    clean = _strip_c_comments(code)
    if not re.search(r"\bclass\s+Solution\b", clean):
        return None
    match = re.search(r"\bstatic\b\s+([^{};=]*?)\bsolve\s*\(", clean)
    if not match:
        return None
    ret_part = re.sub(r"@\w+(\([^()]*\))?", "", match.group(1))
    ret_toks = [tok for tok in ret_part.split() if tok != "final"]
    if not ret_toks:
        return None
    raw_ret = ret_toks[-1]
    found = _balanced_params(clean, match.end() - 1)
    raw_params, _close = found
    if raw_params is None:
        return None
    if "..." in raw_params:
        return None  # varargs: uncountable, caller reviews
    types = []
    for part in _split_top_level(raw_params):
        if not part.strip():
            continue
        typ = _java_param_type(part)
        if typ is None:
            return None
        types.append(typ)
    if raw_ret not in JAVA_TYPES:
        return None
    return types


def go_harness(param_types):
    """main() calling solve with JSON-decoded typed args, OUT: line out."""
    lines = ["package main",
             'import (__dr_json "encoding/json"; __dr_fmt "fmt"; __dr_os "os")',
             "func main() {",
             "var raw []__dr_json.RawMessage",
             "if err := __dr_json.Unmarshal([]byte(__dr_os.Args[1]), &raw); err != nil { __dr_os.Exit(2) }"]
    lines.append("if len(raw) != " + str(len(param_types)) + " { __dr_os.Exit(2) }")
    args = []
    for i, typ in enumerate(param_types):
        lines.append("var p" + str(i) + " " + typ)
        lines.append("if err := __dr_json.Unmarshal(raw[" + str(i) + "], &p" + str(i) + "); err != nil { __dr_os.Exit(1) }")
        args.append("p" + str(i))
    lines.append("out := solve(" + ", ".join(args) + ")")
    lines.append("j, err := __dr_json.Marshal(out)")
    lines.append("if err != nil { __dr_os.Exit(1) }")
    lines.append('__dr_fmt.Println("OUT:" + string(j))')
    lines.append("}")
    return chr(10).join(lines) + chr(10)


_JAVA_COERCE = {"int": "asInt", "long": "asLong", "double": "asDouble",
                 "String": "asString", "boolean": "asBool", "int[]": "asIntArray",
                 "long[]": "asLongArray", "double[]": "asDoubleArray",
                 "String[]": "asStringArray", "boolean[]": "asBoolArray"}


def java_harness(param_types):
    """Main.java calling Solution.solve with JSON-decoded typed args."""
    decls, args = [], []
    for i, typ in enumerate(param_types):
        decls.append("        %s p%d = %s(raw.get(%d));" % (typ, i, _JAVA_COERCE[typ], i))
        args.append("p" + str(i))
    return "\n".join([
        "import java.util.*;",
        "public class Main {",
        "    static class BadArg extends Exception {}",
        "    static String src; static int pos;",
        "    static void skip() {",
        "        while (pos < src.length()) {",
        "            char c = src.charAt(pos);",
        "            if (c == ' ' || c == '\\n' || c == '\\r' || c == '\\t') pos++;",
        "            else break;",
        "        }",
        "    }",
        "    static void expect(String lit) throws BadArg {",
        "        if (!src.startsWith(lit, pos)) throw new BadArg();",
        "        pos += lit.length();",
        "    }",
        "    static Object parse(String s) throws BadArg {",
        "        src = s; pos = 0;",
        "        Object v = parseValue();",
        "        skip();",
        "        if (pos != src.length()) throw new BadArg();",
        "        return v;",
        "    }",
        "    static Object parseValue() throws BadArg {",
        "        skip();",
        "        if (pos >= src.length()) throw new BadArg();",
        "        char c = src.charAt(pos);",
        "        if (c == 'n') { expect(\"null\"); return null; }",
        "        if (c == 't') { expect(\"true\"); return Boolean.TRUE; }",
        "        if (c == 'f') { expect(\"false\"); return Boolean.FALSE; }",
        "        if (c == '\"') return parseString();",
        "        if (c == '[') {",
        "            pos++;",
        "            List<Object> out = new ArrayList<>();",
        "            skip();",
        "            if (pos < src.length() && src.charAt(pos) == ']') { pos++; return out; }",
        "            while (true) {",
        "                out.add(parseValue());",
        "                skip();",
        "                if (pos < src.length() && src.charAt(pos) == ']') { pos++; return out; }",
        "                if (pos >= src.length() || src.charAt(pos) != ',') throw new BadArg();",
        "                pos++;",
        "            }",
        "        }",
        "        if (c == '-' || (c >= '0' && c <= '9')) return parseNumber();",
        "        throw new BadArg();",
        "    }",
        "    static String parseString() throws BadArg {",
        "        pos++;",
        "        StringBuilder sb = new StringBuilder();",
        "        while (true) {",
        "            if (pos >= src.length()) throw new BadArg();",
        "            char c = src.charAt(pos++);",
        "            if (c == '\"') return sb.toString();",
        "            if (c == '\\\\') {",
        "                if (pos >= src.length()) throw new BadArg();",
        "                char e = src.charAt(pos++);",
        "                if (e == '\"') sb.append('\"');",
        "                else if (e == '\\\\') sb.append('\\\\');",
        "                else if (e == '/') sb.append('/');",
        "                else if (e == 'b') sb.append('\\b');",
        "                else if (e == 'f') sb.append('\\f');",
        "                else if (e == 'n') sb.append('\\n');",
        "                else if (e == 'r') sb.append('\\r');",
        "                else if (e == 't') sb.append('\\t');",
        "                else if (e == 'u') {",
        "                    if (pos + 4 > src.length()) throw new BadArg();",
        "                    try { sb.append((char) Integer.parseInt(src.substring(pos, pos + 4), 16)); }",
        "                    catch (NumberFormatException ex) { throw new BadArg(); }",
        "                    pos += 4;",
        "                }",
        "                else throw new BadArg();",
        "            } else if (c < 0x20) {",
        "                throw new BadArg();",
        "            } else {",
        "                sb.append(c);",
        "            }",
        "        }",
        "    }",
        "    static Object parseNumber() throws BadArg {",
        "        int start = pos;",
        "        if (pos < src.length() && src.charAt(pos) == '-') pos++;",
        "        while (pos < src.length() && Character.isDigit(src.charAt(pos))) pos++;",
        "        boolean frac = false;",
        "        if (pos < src.length() && src.charAt(pos) == '.') {",
        "            frac = true; pos++;",
        "            while (pos < src.length() && Character.isDigit(src.charAt(pos))) pos++;",
        "        }",
        "        if (pos < src.length() && (src.charAt(pos) == 'e' || src.charAt(pos) == 'E')) {",
        "            frac = true; pos++;",
        "            if (pos < src.length() && (src.charAt(pos) == '+' || src.charAt(pos) == '-')) pos++;",
        "            while (pos < src.length() && Character.isDigit(src.charAt(pos))) pos++;",
        "        }",
        "        String tok = src.substring(start, pos);",
        "        try {",
        "            if (!frac) return Long.parseLong(tok);",
        "            return Double.parseDouble(tok);",
        "        } catch (NumberFormatException e) { throw new BadArg(); }",
        "    }",
        "    static int asInt(Object v) throws BadArg {",
        "        if (!(v instanceof Long)) throw new BadArg();",
        "        long l = (Long) v;",
        "        if (l < Integer.MIN_VALUE || l > Integer.MAX_VALUE) throw new BadArg();",
        "        return (int) l;",
        "    }",
        "    static long asLong(Object v) throws BadArg {",
        "        if (!(v instanceof Long)) throw new BadArg();",
        "        return (Long) v;",
        "    }",
        "    static double asDouble(Object v) throws BadArg {",
        "        if (v instanceof Long) return (Long) v;",
        "        if (v instanceof Double) return (Double) v;",
        "        throw new BadArg();",
        "    }",
        "    static String asString(Object v) throws BadArg {",
        "        if (!(v instanceof String)) throw new BadArg();",
        "        return (String) v;",
        "    }",
        "    static boolean asBool(Object v) throws BadArg {",
        "        if (!(v instanceof Boolean)) throw new BadArg();",
        "        return (Boolean) v;",
        "    }",
        "    static int[] asIntArray(Object v) throws BadArg {",
        "        if (!(v instanceof List)) throw new BadArg();",
        "        List<Object> l = (List<Object>) v;",
        "        int[] r = new int[l.size()];",
        "        for (int i = 0; i < l.size(); i++) r[i] = asInt(l.get(i));",
        "        return r;",
        "    }",
        "    static long[] asLongArray(Object v) throws BadArg {",
        "        if (!(v instanceof List)) throw new BadArg();",
        "        List<Object> l = (List<Object>) v;",
        "        long[] r = new long[l.size()];",
        "        for (int i = 0; i < l.size(); i++) r[i] = asLong(l.get(i));",
        "        return r;",
        "    }",
        "    static double[] asDoubleArray(Object v) throws BadArg {",
        "        if (!(v instanceof List)) throw new BadArg();",
        "        List<Object> l = (List<Object>) v;",
        "        double[] r = new double[l.size()];",
        "        for (int i = 0; i < l.size(); i++) r[i] = asDouble(l.get(i));",
        "        return r;",
        "    }",
        "    static String[] asStringArray(Object v) throws BadArg {",
        "        if (!(v instanceof List)) throw new BadArg();",
        "        List<Object> l = (List<Object>) v;",
        "        String[] r = new String[l.size()];",
        "        for (int i = 0; i < l.size(); i++) r[i] = asString(l.get(i));",
        "        return r;",
        "    }",
        "    static boolean[] asBoolArray(Object v) throws BadArg {",
        "        if (!(v instanceof List)) throw new BadArg();",
        "        List<Object> l = (List<Object>) v;",
        "        boolean[] r = new boolean[l.size()];",
        "        for (int i = 0; i < l.size(); i++) r[i] = asBool(l.get(i));",
        "        return r;",
        "    }",
        "    static String quote(String s) {",
        "        StringBuilder sb = new StringBuilder();",
        "        sb.append('\"');",
        "        for (int i = 0; i < s.length(); i++) {",
        "            char c = s.charAt(i);",
        "            if (c == '\"') { sb.append('\\\\'); sb.append('\"'); }",
        "            else if (c == '\\\\') { sb.append('\\\\'); sb.append('\\\\'); }",
        "            else if (c == '\\n') { sb.append('\\\\'); sb.append('n'); }",
        "            else if (c == '\\r') { sb.append('\\\\'); sb.append('r'); }",
        "            else if (c == '\\t') { sb.append('\\\\'); sb.append('t'); }",
        "            else if (c == '\\b') { sb.append('\\\\'); sb.append('b'); }",
        "            else if (c == '\\f') { sb.append('\\\\'); sb.append('f'); }",
        "            else if (c < 0x20 || c > 0x7E) sb.append(String.format(\"\\\\u%04x\", (int) c));",
        "            else sb.append(c);",
        "        }",
        "        sb.append('\"');",
        "        return sb.toString();",
        "    }",
        "    static String toJson(Object v) throws BadArg {",
        "        if (v == null) return \"null\";",
        "        if (v instanceof String) return quote((String) v);",
        "        if (v instanceof Long || v instanceof Integer || v instanceof Short || v instanceof Byte) return v.toString();",
        "        if (v instanceof Double) {",
        "            double d = (Double) v;",
        "            if (Double.isNaN(d) || Double.isInfinite(d)) throw new BadArg();",
        "            return Double.toString(d);",
        "        }",
        "        if (v instanceof Boolean) return v.toString();",
        "        if (v instanceof int[]) {",
        "            StringBuilder sb = new StringBuilder(\"[\");",
        "            int[] a = (int[]) v;",
        "            for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(a[i]); }",
        "            return sb.toString() + \"]\";",
        "        }",
        "        if (v instanceof long[]) {",
        "            StringBuilder sb = new StringBuilder(\"[\");",
        "            long[] a = (long[]) v;",
        "            for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(a[i]); }",
        "            return sb.toString() + \"]\";",
        "        }",
        "        if (v instanceof double[]) {",
        "            StringBuilder sb = new StringBuilder(\"[\");",
        "            double[] a = (double[]) v;",
        "            for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(toJson(a[i])); }",
        "            return sb.toString() + \"]\";",
        "        }",
        "        if (v instanceof boolean[]) {",
        "            StringBuilder sb = new StringBuilder(\"[\");",
        "            boolean[] a = (boolean[]) v;",
        "            for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(a[i]); }",
        "            return sb.toString() + \"]\";",
        "        }",
        "        if (v instanceof Object[]) {",
        "            StringBuilder sb = new StringBuilder(\"[\");",
        "            Object[] a = (Object[]) v;",
        "            for (int i = 0; i < a.length; i++) { if (i > 0) sb.append(','); sb.append(toJson(a[i])); }",
        "            return sb.toString() + \"]\";",
        "        }",
        "        if (v instanceof List) {",
        "            StringBuilder sb = new StringBuilder(\"[\");",
        "            List<Object> a = (List<Object>) v;",
        "            for (int i = 0; i < a.size(); i++) { if (i > 0) sb.append(','); sb.append(toJson(a.get(i))); }",
        "            return sb.toString() + \"]\";",
        "        }",
        "        if (v instanceof Map) {",
        "            TreeMap<String, Object> sorted = new TreeMap<>();",
        "            for (Map.Entry<?, ?> e : ((Map<?, ?>) v).entrySet()) sorted.put(String.valueOf(e.getKey()), e.getValue());",
        "            StringBuilder sb = new StringBuilder(\"{\");",
        "            boolean first = true;",
        "            for (Map.Entry<String, Object> e : sorted.entrySet()) {",
        "                if (!first) sb.append(',');",
        "                first = false;",
        "                sb.append(quote(e.getKey()));",
        "                sb.append(':');",
        "                sb.append(toJson(e.getValue()));",
        "            }",
        "            return sb.toString() + \"}\";",
        "        }",
        "        throw new BadArg();",
        "    }",
        "    public static void main(String[] a) {",
        "        try {",
        "            Object v = parse(a[0]);",
        "            if (!(v instanceof List)) System.exit(2);",
        "            List<Object> raw = (List<Object>) v;",
        "            if (raw.size() != %d) System.exit(2);" % len(param_types),
    ] + decls + [
        "            Object out = Solution.solve(%s);" % ", ".join(args),
        '            System.out.println("OUT:" + toJson(out));',
        "        } catch (BadArg e) { System.exit(1); }",
        "        catch (Throwable t) {",
        '            String m = String.valueOf(t.getMessage());',
        "            if (m.length() > 200) m = m.substring(0, 200);",
        '            System.err.println("ERR:" + t.getClass().getSimpleName() + ": " + m);',
        "            System.exit(1);",
        "        }",
        "    }",
        "}",
    ]) + "\n"


def _cxx_normalize_type(typ):
    """One C++ type spelling -> canonical CPP_TYPES member, or None."""
    typ = re.sub(r"\b(const|volatile|static|inline|constexpr|virtual|friend|extern|mutable)\b", "", typ)
    typ = typ.replace("std::", "")
    typ = " ".join(typ.split())
    typ = typ.replace("long long", "long")
    typ = re.sub(r"\s*&+\s*$", "", typ).strip()
    typ = typ.replace(" ", "")
    return typ if typ in CPP_TYPES else None


def _cxx_param_type(part):
    """One `Type name` (or bare type) declaration -> CPP_TYPES member, or None."""
    part = part.split("=", 1)[0].strip()  # default value
    if not part:
        return None
    match = re.match(r"^(.*?)\s*([A-Za-z_]\w*)$", part)
    if not match:
        return None
    pre = match.group(1).strip()
    typ_raw = match.group(2) if not pre else pre
    return _cxx_normalize_type(typ_raw)


def cxx_signature(code):
    """Param types of free-function `solve`, or None when unusable/unsupported."""
    clean = _strip_c_comments(code)
    match = re.search(r"(?<![\w:>.])solve\s*\(", clean)
    if not match:
        return None
    raw_params = _balanced_params(clean, match.end() - 1)[0]
    if raw_params is None:
        return None
    if "..." in raw_params:
        return None  # variadic: uncountable, caller reviews
    types = []
    for part in _split_top_level(raw_params):
        if not part.strip():
            continue
        typ = _cxx_param_type(part)
        if typ is None:
            return None
        types.append(typ)
    head = re.split(r"[;{}]", clean[:match.start()])[-1]
    after = clean[match.end() - 1:]
    _, close = _balanced_params(clean, match.end() - 1)
    rest = after[close - (match.end() - 1) + 1:]
    mret = re.match(r"\s*->\s*([^{};,]+)", rest)
    if mret:
        ret_raw = mret.group(1)
    else:
        toks = head.split()
        ret_raw = " ".join(toks[-3:])
    ret = _cxx_normalize_type(ret_raw)
    if ret is None:
        return None
    return types


def _cxx_qualify(typ):
    """Canonical type -> code spelling (re-adds std:: qualification)."""
    if typ in ("int", "long", "double", "bool"):
        return typ
    if typ == "string":
        return "std::string"
    match = re.fullmatch(r"vector<(.*)>", typ)
    if match:
        return "std::vector<" + _cxx_qualify(match.group(1)) + ">"
    raise BuildError("cannot spell type " + typ)


def cxx_harness(param_types):
    """Includes + main() calling solve with JSON-decoded typed args."""
    lines = ["#include <nlohmann/json.hpp>",
             "#include <iostream>",
             "#include <string>",
             "#include <vector>",
             "#include <climits>",
             "//__USER_CODE__",
             "int main(int argc, char** argv) {",
             "    if (argc < 2) return 2;",
             "    nlohmann::json args;",
             "    try { args = nlohmann::json::parse(argv[1]); }",
             "    catch (...) { return 2; }",
             "    if (!args.is_array() || args.size() != " + str(len(param_types)) + ") return 2;",
             "    try {"]
    args = []
    for i, typ in enumerate(param_types):
        ctyp = _cxx_qualify(typ)
        lines.append("        " + ctyp + " p" + str(i) + " = args.at(" + str(i) + ").get<" + ctyp + ">();")
        args.append("p" + str(i))
    lines.append("        auto out = solve(" + ", ".join(args) + ");")
    lines.append('        std::cout << "OUT:" << nlohmann::json(out).dump() << std::endl;')
    lines.append("    } catch (...) { return 1; }")
    lines.append("    return 0;")
    lines.append("}")
    return chr(10).join(lines) + chr(10)


def _vendor_dir():
    """Repo-vendored third-party headers (nlohmann/json.hpp)."""
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")


def _prepare_cxx(tmpdir, stem, harness, code):
    """Write user code + harness main, g++ both; return exe path."""
    gxx = (INTERPS.get("c++") or [None])[0]
    if gxx is None:
        raise BuildError("c++ toolchain missing")
    src = os.path.join(tmpdir, stem + ".cpp")
    exe = os.path.join(tmpdir, stem)
    try:
        with open(src, "w", encoding="utf-8") as handle:
            if not code.endswith("\n"):
                code = code + "\n"
            handle.write(harness.replace("//__USER_CODE__", code, 1))
    except OSError as exc:
        raise BuildError("cannot write program file: " + str(exc)) from exc
    env = {"PATH": SPAWN_ENV["PATH"], "HOME": os.path.expanduser("~")}
    try:
        proc = subprocess.run([gxx, "-O0", "-std=c++17", "-I" + _vendor_dir(), src, "-o", exe],
                              cwd=tmpdir, env=env, capture_output=True,
                              timeout=CPP_BUILD_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise BuildError("build timed out")
    except Exception as exc:
        raise BuildError("build failed: " + str(exc))
    if proc.returncode != 0:
        raise BuildError(_err_line(proc.stderr, tmpdir) or "compile failed")
    return exe


CS_BUILD_TIMEOUT = 60
CS_TYPES = {"int", "long", "double", "string", "bool",
            "int[]", "long[]", "double[]", "string[]", "bool[]"}
_CS_MODIFIERS = ("ref", "out", "in", "params", "this")


def cs_signature(ref_code):
    """Canonical param types of `Solve`/`solve`, or None when unusable."""
    clean = _strip_c_comments(ref_code)
    match = re.search(r"(?<![\w:.])[Ss]olve\s*\(", clean)
    if not match:
        return None
    raw = _balanced_params(clean, match.end() - 1)[0]
    if raw is None:
        return None
    if not raw.strip():
        return []
    types = []
    for part in _split_top_level(raw):
        chunks = part.partition("=")[0].strip().split()
        while chunks and chunks[0] in _CS_MODIFIERS:
            chunks.pop(0)
        if len(chunks) < 2:
            return None
        typ = "".join(chunks[:-1]).rstrip("?")
        if typ not in CS_TYPES:
            return None
        types.append(typ)
    return types


def _cs_reader(typ, idx):
    """JsonElement extraction expression for one canonical type."""
    cell = "root[" + str(idx) + "]"
    if typ == "int":
        return cell + ".GetInt32()"
    if typ == "long":
        return cell + ".GetInt64()"
    if typ == "double":
        return cell + ".GetDouble()"
    if typ == "string":
        return cell + ".GetString()"
    if typ == "bool":
        return cell + ".GetBoolean()"
    elem = {"int[]": "GetInt32", "long[]": "GetInt64",
            "double[]": "GetDouble", "string[]": "GetString",
            "bool[]": "GetBoolean"}[typ]
    return cell + ".EnumerateArray().Select(e => e." + elem + "()).ToArray()"


def cs_harness(param_types):
    """Usings + marker + Main calling Solution.Solve with decoded args."""
    lines = ["using System;",
             "using System.Linq;",
             "using System.Text.Json;",
             "//__USER_CODE__",
             "public static class Harness {",
             "    public static int Main(string[] args) {",
             "        if (args.Length < 1) return 2;",
             "        try {",
             "            var root = JsonDocument.Parse(args[0]).RootElement;",
             "            if (root.ValueKind != JsonValueKind.Array || root.GetArrayLength() != " + str(len(param_types)) + ") return 2;"]
    args = []
    for i, typ in enumerate(param_types):
        lines.append("            " + typ + " p" + str(i) + " = " + _cs_reader(typ, i) + ";")
        args.append("p" + str(i))
    lines.append("            var o = Solution.Solve(" + ", ".join(args) + ");")
    lines.append("            Console.Write(\"OUT:\" + JsonSerializer.Serialize(o));")
    lines.append("        } catch { return 1; }")
    lines.append("        return 0;")
    lines.append("    }")
    lines.append("}")
    return chr(10).join(lines) + chr(10)


def _cs_ref_dir(root):
    """(ref dir, fx version, tfm) of the newest ref pack, or None."""
    try:
        base = os.path.join(root, "packs", "Microsoft.NETCore.App.Ref")
        versions = sorted((v for v in os.listdir(base)
                           if re.fullmatch(r"\d+\.\d+\.\d+", v)),
                          key=lambda v: tuple(int(p) for p in v.split(".")))
    except OSError:
        return None
    for version in reversed(versions):
        refbase = os.path.join(base, version, "ref")
        try:
            tfms = sorted(d for d in os.listdir(refbase)
                          if d.startswith("net") and os.path.isdir(os.path.join(refbase, d)))
        except OSError:
            continue
        for tfm in reversed(tfms):
            refdir = os.path.join(refbase, tfm)
            if os.path.isfile(os.path.join(refdir, "System.Runtime.dll")):
                return (refdir, version, tfm)
    return None


def _find_cs_sdk():
    """(csc.dll, ref dir, fx version, tfm), or None when SDK absent/broken."""
    dotnetbin = (INTERPS.get("c#") or [None])[0]
    roots = []
    env_root = os.environ.get("DOTNET_ROOT")
    if env_root:
        roots.append(env_root)
    if dotnetbin is not None:
        roots.append(os.path.dirname(os.path.abspath(dotnetbin)))
    for root in roots:
        try:
            sdkbase = os.path.join(root, "sdk")
            versions = sorted((v for v in os.listdir(sdkbase)
                               if re.fullmatch(r"\d+\.\d+\.\d+", v)),
                              key=lambda v: tuple(int(p) for p in v.split(".")))
        except OSError:
            continue
        for version in reversed(versions):
            csc = os.path.join(sdkbase, version, "Roslyn", "bincore", "csc.dll")
            if not os.path.isfile(csc):
                continue
            ref = _cs_ref_dir(root)
            if ref is None:
                continue
            return (csc,) + ref
    return None


def _prepare_cs(tmpdir, stem, harness, code):
    """Write Main.cs + runtimeconfig, csc once; return dll path."""
    sdk = _find_cs_sdk()
    dotnetbin = (INTERPS.get("c#") or [None])[0]
    if sdk is None or dotnetbin is None:
        raise BuildError("c# toolchain missing")
    csc, refdir, fx, tfm = sdk
    src = os.path.join(tmpdir, stem + ".cs")
    dll = os.path.join(tmpdir, stem + ".dll")
    rsp = os.path.join(tmpdir, "refs.rsp")
    try:
        if not code.endswith(chr(10)):
            code = code + chr(10)
        # Bare method style needs no class: wrap it in Solution, defaulting
        # the method to public so the harness can call it. shortcut: stray
        # top-level statements still fail compile.
        code = re.sub(r"(?<![\w:.])solve\s*\(", "Solve(", code)
        if not re.search(r"\bclass\s+Solution\b", code):
            code = re.sub(r"(?m)^(?=[ \t]*(?!public\b|private\b|internal\b|protected\b)(?:static\s+)?(?:[\w<>,\.\[\]\?]+\s+)+?Solve\s*\()", "public ", code, count=1)
            code = "public class Solution {\n" + code + "\n}\n"
        # Static or instance call to match this side's declaration.
        call = "Solution.Solve("
        if not re.search(r"\bstatic\b[^{};=]*\bSolve\s*\(", _strip_c_comments(code)):
            call = "new Solution().Solve("
        with open(src, "w", encoding="utf-8") as handle:
            handle.write(harness.replace("//__USER_CODE__", code, 1).replace("Solution.Solve(", call, 1))
        with open(os.path.join(tmpdir, stem + ".runtimeconfig.json"), "w", encoding="utf-8") as handle:
            handle.write("{\"runtimeOptions\":{\"tfm\":\"" + tfm + "\",\"framework\":{\"name\":\"Microsoft.NETCore.App\",\"version\":\"" + fx + "\"},\"rollForward\":\"LatestMinor\"}}")
        with open(rsp, "w", encoding="utf-8") as handle:
            for name in sorted(os.listdir(refdir)):
                if name.endswith(".dll"):
                    handle.write("-r:" + os.path.join(refdir, name) + chr(10))
    except OSError as exc:
        raise BuildError("cannot write program file: " + str(exc)) from exc
    env = {"PATH": SPAWN_ENV["PATH"], "HOME": os.path.expanduser("~")}
    try:
        proc = subprocess.run([dotnetbin, csc, "-nologo", "-out:" + dll,
                               "-target:exe", "@" + rsp, src],
                              cwd=tmpdir, env=env, capture_output=True,
                              timeout=CS_BUILD_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise BuildError("build timed out")
    except Exception as exc:
        raise BuildError("build failed: " + str(exc))
    if proc.returncode != 0:
        raise BuildError(_err_line(proc.stderr, tmpdir) or "compile failed")
    return dll


def harness_for(language, ref_lang, ref_code):
    """Harness source for one side, or '' when the side is interpreted."""
    if language not in COMPILED:
        return ""
    if ref_lang != language:
        raise HarnessError(language + " attempts need a " + language + " reference")
    if language == "go":
        types = go_signature(ref_code)
        if types is None:
            raise BuildError("reference solve() has no usable go signature")
        return go_harness(types)
    if language == "java":
        types = java_signature(ref_code)
        if types is None:
            raise BuildError("reference solve() has no usable java signature")
        return java_harness(types)
    if language == "c++":
        types = cxx_signature(ref_code)
        if types is None:
            raise BuildError("reference solve() has no usable c++ signature")
        return cxx_harness(types)
    if language == "c#":
        types = cs_signature(ref_code)
        if types is None:
            raise BuildError("reference Solve() has no usable c# signature")
        return cs_harness(types)
    raise BuildError("no harness for " + language)


def prepare_program(tmpdir, stem, language, code, harness=""):
    """Write source (+harness) and compile when needed; return runnable path."""
    if language not in COMPILED:
        return write_program(tmpdir, stem, language, code)
    if language == "java":
        return _prepare_java(tmpdir, harness, code)
    if language == "c++":
        return _prepare_cxx(tmpdir, stem, harness, code)
    if language == "c#":
        return _prepare_cs(tmpdir, stem, harness, code)
    gobin = (INTERPS.get("go") or [None])[0]
    if gobin is None:
        raise BuildError("go toolchain missing")
    src = os.path.join(tmpdir, stem + ".go")
    exe = os.path.join(tmpdir, stem)
    try:
        with open(src, "w", encoding="utf-8") as handle:
            handle.write(harness)
            handle.write(chr(10))
            handle.write(_strip_go_package(code))
    except OSError as exc:
        raise BuildError("cannot write program file: " + str(exc)) from exc
    env = {"PATH": SPAWN_ENV["PATH"], "HOME": os.path.expanduser("~")}
    try:
        proc = subprocess.run([gobin, "build", "-o", exe, src],
                              cwd=tmpdir, env=env, capture_output=True,
                              timeout=GO_BUILD_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise BuildError("build timed out")
    except Exception as exc:
        raise BuildError("build failed: " + str(exc))
    if proc.returncode != 0:
        raise BuildError(_err_line(proc.stderr, tmpdir) or "compile failed")
    return exe


def _strip_java_package(code):
    """Drop `package x;` lines; pasted full programs stay compilable."""
    out = []
    for line in code.splitlines(keepends=True):
        if re.match(r"\s*package\s+[\w.]+\s*;\s*$", line):
            continue
        out.append(line)
    return "".join(out)


def _javac():
    """javac binary path, or None when the JDK is absent."""
    found = shutil.which("javac", path=SPAWN_ENV["PATH"])
    if found:
        return found
    javabin = (INTERPS.get("java") or [None])[0]
    if javabin is not None:
        try:
            cand = os.path.join(os.path.dirname(javabin), "javac")
            if os.path.isfile(cand) and os.access(cand, os.X_OK):
                return cand
        except (OSError, ValueError):
            pass
    return None


def _prepare_java(tmpdir, harness, code):
    """Write Solution.java + Main.java, javac both; return classpath dir."""
    javac = _javac()
    if javac is None:
        raise BuildError("java toolchain missing")
    sol = os.path.join(tmpdir, "Solution.java")
    main = os.path.join(tmpdir, "Main.java")
    try:
        with open(sol, "w", encoding="utf-8") as handle:
            handle.write(_strip_java_package(code))
        with open(main, "w", encoding="utf-8") as handle:
            handle.write(harness)
    except OSError as exc:
        raise BuildError("cannot write program file: " + str(exc)) from exc
    env = {"PATH": SPAWN_ENV["PATH"], "HOME": os.path.expanduser("~")}
    try:
        proc = subprocess.run([javac, sol, main],
                              cwd=tmpdir, env=env, capture_output=True,
                              timeout=JAVA_BUILD_TIMEOUT)
    except subprocess.TimeoutExpired:
        raise BuildError("build timed out")
    except Exception as exc:
        raise BuildError("build failed: " + str(exc))
    if proc.returncode != 0:
        # javac trails a "N errors" summary as the last line; the first
        # error line is the informative one (later ones are often cascades).
        kept = [ln for ln in (proc.stderr or b"").splitlines()
                if not re.match(rb"^\\d+ errors?\\s*$", ln.strip())]
        raise BuildError(_err_line(b"\n".join(kept), tmpdir) or "compile failed")
    return tmpdir


def _count_params(raw):
    raw = raw.strip()
    if not raw:
        return 0
    if "{" in raw or "[" in raw or "*" in raw or "&" in raw:
        return None  # destructuring/splat: arity unknowable, caller reviews
    return len([part for part in raw.split(",") if part.strip()])


def _split_top_level(raw):
    '''Split on commas at bracket depth 0, quotes respected.'''
    parts, depth, cur = [], 0, []
    openers = {"(": ")", "[": "]", "{": "}", "<": ">"} 
    closers = set(openers.values())
    quote = None
    i = 0
    while i < len(raw):
        ch = raw[i]
        if quote:
            cur.append(ch)
            if ch == chr(92) and i + 1 < len(raw):
                cur.append(raw[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in ("'", '"', "`"):
            quote = ch
            cur.append(ch)
        elif ch in openers:
            depth += 1
            cur.append(ch)
        elif ch in closers:
            depth = max(0, depth - 1)
            cur.append(ch)
        elif ch == "," and depth == 0:
            parts.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
        i += 1
    parts.append("".join(cur))
    return parts


def _count_ts_params(raw):
    '''Arity of a TS param list, or None when it cannot be known statically.'''
    raw = raw.strip()
    if not raw:
        return 0
    if "..." in raw:
        return None  # rest params: arity unknowable, caller reviews
    parts = [part for part in _split_top_level(raw) if part.strip()]
    for part in parts:
        stripped = part.strip()
        if stripped.startswith("{") or stripped.startswith("["):
            return None  # destructuring: arity unknowable, caller reviews
    return len(parts)


def get_arity(language, code):
    """Number of solve() params, or None when the entrypoint is unusable."""
    if language == "python":
        # Pasted code often arrives uniformly indented; dedent is a no-op
        # for normally formatted programs and rescues indented pastes.
        code = textwrap.dedent(code)
        try:
            tree = ast.parse(code)
        except SyntaxError:
            return None
        for node in ast.walk(tree):
            if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) \
                    and node.name == "solve":
                args = node.args
                if args.vararg or args.kwonlyargs or args.kwarg:
                    return None
                return len(args.args)
        return None
    if language == "javascript":
        patterns = [
            r"function\s+solve\s*\(([^)]*)\)",
            r"(?:const|let|var)\s+solve\s*=\s*(?:async\s*)?\(([^)]*)\)\s*=>",
            r"(?:const|let|var)\s+solve\s*=\s*(?:async\s*)?function\s*\(([^)]*)\)",
        ]
        for pattern in patterns:
            match = re.search(pattern, code)
            if match:
                return _count_params(match.group(1))
        return None
    if language == "typescript":
        # Same shapes as JS, plus optional generics and type annotations.
        # Return types sit outside the capture group; in-group annotations
        # (incl. []/generics/unions) are split depth-aware below.
        patterns = [
            "function[ \t]+solve(?:<[^<>]*>)?[ \t]*[(]([^)]*)[)]",
            "(?:const|let|var)[ \t]+solve[ \t]*(?::[ \t]*[^=;]+?)?=[ \t]*(?:async[ \t]+)?[(]([^)]*)[)](?:[ \t]*:[ 	]*[^=;]+?)?[ \t]*=>",
            "(?:const|let|var)[ \t]+solve[ \t]*(?::[ \t]*[^=;]+?)?=[ \t]*(?:async[ \t]+)?function(?:<[^<>]*>)?[ \t]*[(]([^)]*)[)]",
        ]
        for pattern in patterns:
            match = re.search(pattern, code)
            if match:
                return _count_ts_params(match.group(1))
        return None
    if language == "go":
        match = re.search("func +solve *[(]([^)]*)[)]", code)
        if not match:
            return None
        raw = match.group(1)
        if raw.count("(") != raw.count(")"):
            return None  # func-typed params: uncountable, caller reviews
        if "..." in raw:
            return None  # variadic: uncountable, caller reviews
        return len([part for part in _split_top_level(raw) if part.strip()])
    if language == "java":
        # `static solve` (any modifiers/order); params scanned with balance
        # so generic and func-typed params don't truncate the list.
        clean = _strip_c_comments(code)
        match = re.search(r"\bstatic\b[^{};=]*\bsolve\s*\(", clean)
        if not match:
            return None
        raw = _balanced_params(clean, match.end() - 1)[0]
        if raw is None:
            return None
        if "..." in raw:
            return None  # varargs: uncountable, caller reviews
        return len([part for part in _split_top_level(raw) if part.strip()])
    if language == "c++":
        # Free function `solve` (member/qualified names excluded); params
        # scanned with balance so template types don't truncate the list.
        clean = _strip_c_comments(code)
        match = re.search(r"(?<![\w:>.])solve\s*\(", clean)
        if not match:
            return None
        raw = _balanced_params(clean, match.end() - 1)[0]
        if raw is None:
            return None
        if "..." in raw:
            return None  # variadic: uncountable, caller reviews
        return len([part for part in _split_top_level(raw) if part.strip()])
    if language == "c#":
        # `Solve`/`solve` method (qualified calls excluded); defaults don't change
        # arity, generic methods have none (angle bracket breaks the match).
        clean = _strip_c_comments(code)
        match = re.search(r"(?<![\w:.])[Ss]olve\s*\(", clean)
        if not match:
            return None
        raw = _balanced_params(clean, match.end() - 1)[0]
        if raw is None:
            return None
        return len([part for part in _split_top_level(raw) if part.strip()])
    if language == "ruby":
        match = re.search(r"def\s+solve(?:\s*\(([^)]*)\)|\s+([^\n;#:]*))?", code)
        if not match:
            return None
        raw = match.group(1) if match.group(1) is not None else (match.group(2) or "")
        return _count_params(raw)
    return None


EDGE_INTS = [0, 1, -1, 2, -2, 10, -10, 100, -100, 1000, -1000,
             2 ** 31 - 1, -(2 ** 31), 2 ** 31, SAFE_MAX, -SAFE_MAX]


def _rand_int(rng):
    roll = rng.random()
    if roll < 0.6:
        return rng.randint(-1000, 1000)
    if roll < 0.85:
        return rng.randint(-1000000, 1000000)
    return rng.randint(-SAFE_MAX, SAFE_MAX)


def _rand_list(rng):
    return [rng.randint(-100, 100) for _ in range(rng.randint(0, 8))]


def _rand_str(rng):
    return "".join(rng.choice("abcxyz") for _ in range(rng.randint(0, 6)))


def _gen_value(rng):
    roll = rng.random()
    if roll < 0.60:
        return _rand_int(rng)
    if roll < 0.88:
        return _rand_list(rng)
    return _rand_str(rng)


def gen_inputs(seed, count, arity):
    """Seed -> up to `count` arg-lists: edge cases, then PRNG values by type.

    Deterministic in (seed, count, arity). Broad by type on purpose: inputs the
    reference crashes on are dropped reference-first by the caller, so tasks
    with narrow domains (int-only, list-only) still get a large valid set.
    """
    rng = random.Random(seed)
    cases = []  # type: list
    if arity == 1:
        # Round-robin across types from position 0: small-N consumers (like
        # the 10-case creation dry-run) must see every shape, not scalars only.
        scalars = [[value] for value in EDGE_INTS]
        singles = [[[value]] for value in EDGE_INTS]
        mixed = [[], [""], ["abc"], [[]], [[1, 2, 3]], [[-5, 0, 5]],
                 ["hello world"], [[0]], ["a"], ["x" * 100]]
        for i in range(max(len(scalars), len(singles), len(mixed))):
            for group in (scalars, singles, mixed):
                if i < len(group):
                    cases.append(group[i])
    elif arity == 2:
        intpairs = []
        for value in EDGE_INTS[:8]:
            intpairs += [[value, value], [0, value], [value, 0]]
        mixed2 = [[[1, 2, 3], 2], [[], 0], [[5], -1], [[0], [1]], [["a"], ["b"]],
                  [[0], 0], [[1], 1], [[-1], -1], [[1, 2, 3], 6], [[5, 5], 10],
                  [[100], -100], [[-5, 0, 5], 0], [[1000], 1000], [[-1000], -1000],
                  [[2, 2], 4], [[0, 0], 0], [[7], 7], [[1, 2], 3], [[-1, 1], 0],
                  [[2147483647], 0], [[-2147483648], 0]]
        # (list, int) shapes must clear the valid-input threshold on their own:
        # 20 banked + random tail vs threshold 20 at N=100 (mixed-signature tasks).
        for i in range(max(len(intpairs), len(mixed2))):
            for group in (intpairs, mixed2):
                if i < len(group):
                    cases.append(group[i])
    elif arity > 2:
        cases += [[0] * arity, [1] * arity,
                  list(range(arity)), [-1] * arity]
    else:  # arity 0: nullary solve takes no inputs
        return [[]]
    while len(cases) < count:
        if arity:
            cases.append([_gen_value(rng) for _ in range(arity)])
        else:
            cases.append([])
    seen = []
    seen_keys = set()
    for case in cases:
        key = json.dumps(case, sort_keys=True)
        if key not in seen_keys:
            seen_keys.add(key)
            seen.append(case)
        if len(seen) >= count:
            break
    return seen[:count]


def canon(value):
    """Normalize one side's output so equivalent values compare equal across
    runtimes: tuples->lists, integral floats->int, dict keys sorted."""
    if isinstance(value, bool):
        return value
    if isinstance(value, float):
        if value.is_integer() and abs(value) < 2 ** 53:
            return int(value)
        return value
    if isinstance(value, (list, tuple)):
        return [canon(item) for item in value]
    if isinstance(value, dict):
        return {str(key): canon(value[key]) for key in sorted(value, key=str)}
    return value


def equal(first, second):
    return canon(first) == canon(second)


def _err_line(stderr_bytes, tmpdir):
    """Last stderr line, sanitized for reasons: no tmp paths, capped length."""
    try:
        text = (stderr_bytes or b"").decode("utf-8", errors="replace")
    except Exception:
        return None
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    if not lines:
        return None
    errs = [line[4:] for line in lines if line.startswith("ERR:")]
    line = errs[-1] if errs else lines[-1]
    line = line.replace(tmpdir, "<workdir>")
    return line[:200] if len(line) > 200 else line


def run_one(language, prog, args, timeout, cwd):
    """Run one case. Returns (status, value, err); value is set only for "ok".

    Statuses: ok | crash | timeout | truncated | bad_output. Tracebacks and
    program output never leave this function except one sanitized stderr line —
    the caller only reports counts, failing inputs and that line, so reference
    text and expected outputs cannot leak into reasons (spec section 4).
    """
    if language == "c#":
        dotnetbin = (INTERPS.get("c#") or [None])[0]
        if dotnetbin is None:  # runtime missing: every case fails, caller reviews
            return ("crash", None, "runtime missing")
        cmd = [dotnetbin, prog]
    elif language == "java":
        javabin = (INTERPS.get("java") or [None])[0]
        if javabin is None:  # runtime missing: every case fails, caller reviews
            return ("crash", None, "runtime missing")
        cmd = [javabin, "-cp", prog, "Main"]
    elif language in COMPILED:
        cmd = [prog]
    else:
        cmd = INTERPS.get(language)
        if cmd is None:  # runtime missing: every case fails, caller reviews
            return ("crash", None, "runtime missing")
        cmd = cmd + [prog]
    cmd = cmd + [json.dumps(args)]
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                cwd=cwd, env=SPAWN_ENV, start_new_session=True)
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            # Kill the whole process group: attempts may spawn grandchildren
            # that outlive the direct child and clog the runner slots.
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except OSError:
                pass
            proc.wait()
            return ("timeout", None, None)
    except Exception:
        return ("crash", None, None)
    out = out or b""
    if len(out) > STDOUT_CAP:
        return ("truncated", None, None)
    if proc.returncode != 0:
        return ("crash", None, _err_line(err, cwd))
    try:
        text = out.decode("utf-8", errors="strict")
    except Exception:
        return ("bad_output", None, None)
    for line in text.splitlines():
        if line.startswith("OUT:"):
            try:
                return ("ok", json.loads(line[4:]), None)
            except Exception:
                return ("bad_output", None, None)
    return ("bad_output", None, None)
