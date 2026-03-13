#!/usr/bin/env bash
# ct-search.sh — dual-mode BM25+Cipher search library
# Sourceable library providing ct_search_run and ct_search_with_cipher functions.

_CT_SEARCH_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ct_search_run <root> <query> [top]
# BM25-only search with scoring formula:
#   final_score = (0.6 × bm25 + 0.2 × importance/100 + 0.2 × recency) × maturityBoost
# Outputs JSON array sorted by final_score descending.
ct_search_run() {
  local root="$1" query="$2" top="${3:-10}"

  if [ -z "$query" ]; then
    echo "[]"
    return 0
  fi

  local bm25_json
  bm25_json=$(python3 "${_CT_SEARCH_SCRIPT_DIR}/bm25.py" "$root" "$query" "$top")

  echo "$bm25_json" | python3 -c "
import json, sys

bm25 = json.load(sys.stdin)
limit = int('$top')

results = []
for r in bm25:
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r.get('maturity', 'draft') == 'core' else 1.0

    score = (0.6 * bm25_s + 0.2 * imp_norm + 0.2 * rec) * maturity_boost
    r['final_score'] = round(score, 4)
    results.append(r)

results.sort(key=lambda x: x['final_score'], reverse=True)
print(json.dumps(results[:limit], indent=2))
"
}

# ct_search_with_cipher <root> <query> <cipher_json> [top]
# BM25+Cipher merged search with scoring formula:
#   final_score = (0.5 × cipher + 0.3 × bm25 + 0.1 × importance/100 + 0.1 × recency) × maturityBoost
# Outputs JSON array sorted by final_score descending.
ct_search_with_cipher() {
  local root="$1" query="$2" cipher_json="$3" top="${4:-10}"

  if [ -z "$query" ]; then
    echo "[]"
    return 0
  fi

  local bm25_json
  bm25_json=$(python3 "${_CT_SEARCH_SCRIPT_DIR}/bm25.py" "$root" "$query" "$top")

  python3 -c "
import json, sys

bm25 = json.loads(sys.argv[1])
cipher = json.loads(sys.argv[2])
limit = int(sys.argv[3])

cipher_map = {}
for c in cipher:
    key = c.get('path', c.get('title', ''))
    cipher_map[key] = c.get('similarity', 0)

results = []
bm25_paths = set()
for r in bm25:
    bm25_paths.add(r['path'])
    cipher_sim = cipher_map.get(r['path'], 0)
    imp_norm = r['importance'] / 100.0
    rec = r['recency']
    bm25_s = r['bm25_score']
    maturity_boost = 1.15 if r.get('maturity', 'draft') == 'core' else 1.0

    score = (0.5 * cipher_sim + 0.3 * bm25_s + 0.1 * imp_norm + 0.1 * rec) * maturity_boost
    r['cipher_similarity'] = cipher_sim
    r['final_score'] = round(score, 4)
    results.append(r)

for c in cipher:
    path = c.get('path', '')
    if path and path not in bm25_paths:
        sim = c.get('similarity', 0)
        score = (0.5 * sim) * 1.0
        results.append({
            'path': path,
            'title': c.get('title', ''),
            'cipher_similarity': sim,
            'bm25_score': 0,
            'final_score': round(score, 4),
            'maturity': 'unknown',
            'importance': 0,
            'recency': 0,
        })

results.sort(key=lambda x: x['final_score'], reverse=True)
print(json.dumps(results[:limit], indent=2))
" "$bm25_json" "$cipher_json" "$top"
}
