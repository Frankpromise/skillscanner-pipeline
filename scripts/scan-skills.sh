#!/usr/bin/env bash
# Scan each skill folder passed as an argument. Exit 1 if any must be blocked.
set -uo pipefail

mkdir -p reports
summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
echo "| Skill | Score | Verdict |" >> "$summary"
echo "|---|---|---|" >> "$summary"
status=0

for skill in "$@"; do
  name=$(basename "$skill")
  skillspector scan "$skill" --no-llm -f json -o "reports/$name.json"

  if [ $? -eq 2 ]; then
    echo "::error::$name: scan failed. Blocking, because we couldn't check it."
    echo "| $name | - | ❌ scan error |" >> "$summary"
    status=1
    continue
  fi

  score=$(jq -r .risk_assessment.score "reports/$name.json")
  rec=$(jq -r .risk_assessment.recommendation "reports/$name.json")

  case "$rec" in
    SAFE)    echo "✅ $name: $score SAFE";                                 icon="✅" ;;
    CAUTION) echo "::warning::$name scored $score (CAUTION). Needs human review."; icon="⚠️" ;;
    *)       echo "::error::$name scored $score (DO_NOT_INSTALL)";         icon="❌"; status=1 ;;
  esac
  echo "| $name | $score | $icon $rec |" >> "$summary"
done

exit $status
