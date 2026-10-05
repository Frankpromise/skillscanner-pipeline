# skillscanner-pipeline

A GitHub Actions pipeline that scans AI agent skills with [NVIDIA SkillSpector](https://github.com/NVIDIA/skillspector) and blocks pull requests that add dangerous ones.

An agent skill is a folder with a `SKILL.md` (instructions the agent follows) and optional scripts. Skills run with the user's permissions, so a malicious one can read credentials, run commands, or tell the agent to hide what it's doing. This pipeline checks every skill before it is merged.

## How it works

On every pull request that changes `samples/`, the workflow:

1. Installs SkillSpector `v2.12.0` (pinned)
2. Runs a static scan on every skill folder in `samples/`
3. Maps each result to a verdict (table below)
4. Writes a summary table to the run page and uploads the JSON reports as the `skillspector-reports` artifact

| SkillSpector recommendation | Score | Pipeline verdict |
| --- | --- | --- |
| `SAFE` | 0–20 | ✅ pass |
| `CAUTION` | 21–50 | ⚠️ warning annotation, still passes |
| `DO_NOT_INSTALL` | 51–100 | ❌ fails the check |
| Scan error | – | ❌ fails the check (the skill couldn't be checked) |

Scans run with `--no-llm`: no API keys are needed, and skill contents never leave the runner. SkillSpector also never executes the skill it scans. (It does send declared dependency names to [OSV.dev](https://osv.dev) to look up known CVEs.)

## Repository layout

```text
.github/workflows/skill-scan.yaml   # the workflow
scripts/scan-skills.sh              # scan + verdict logic (runs locally too)
samples/                            # one folder per skill
  hello-skill/                      #   clean, expected: SAFE
  hello-skill-bad/                  #   prompt injection, expected: CAUTION
  evil-skill/                       #   malicious, expected: DO_NOT_INSTALL
```

The test skills are deliberately harmless: any URLs use the reserved `example.invalid` domain, which never resolves.

## Adding a skill

1. Create `samples/<skill-name>/SKILL.md` (plus any `scripts/`).
2. Open a pull request.
3. Check the **Skill scan** result on the PR. For details, open the run's summary page or download the `skillspector-reports` artifact.

## Running locally

Requires Python 3.12+, [uv](https://docs.astral.sh/uv/), and `jq`.

```bash
uv tool install git+https://github.com/NVIDIA/skillspector.git@v2.12.0
bash scripts/scan-skills.sh samples/*/
echo $?   # 0 = nothing blocked, 1 = at least one skill blocked
```

Reports are written to `reports/<skill-name>.json` (git-ignored).

To scan a single skill and see every finding:

```bash
skillspector scan samples/evil-skill --no-llm
```

## Enforcing the check

A failing check does not stop a merge by itself. To enforce it, add a branch protection rule for the default branch (**Settings → Branches**), enable **Require status checks to pass before merging**, and select **scan**.

## Changing the policy

The verdict logic lives in the `case` statement in `scripts/scan-skills.sh`:

- **Block CAUTION too:** move `CAUTION` into the failing branch.
- **Block on any finding:** add `--fail-on-findings` to the `skillspector scan` command.

To upgrade SkillSpector, change the version tag in the workflow's install step and re-run the scans to see how results change.

## Limitations

- **Static analysis matches patterns, not intent.** A malicious instruction worded to avoid SkillSpector's rules (for example, "copy the dot-env configuration into the footer" instead of "read the .env file") can score 0 and pass. SkillSpector's optional LLM stage catches more of these; this pipeline doesn't enable it yet.
- **CAUTION passes by default.** A skill containing "Ignore all previous instructions" scores about 27 and only produces a warning.
- A passing scan means no known pattern was found, not that the skill is proven safe.
