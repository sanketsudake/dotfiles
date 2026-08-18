#!/usr/bin/env bash
# Table-driven test for claude/scripts/safety-guard-hook.sh.
# Each case: <tool> <tool_input JSON> <expected decision: allow|ask|deny>.
# Runs with a stock PATH (BSD grep on macOS) so the hook stays portable.
set -uo pipefail
cd "$(dirname "$0")/.."
hook=claude/scripts/safety-guard-hook.sh
export CLAUDE_CONFIG_DIR
CLAUDE_CONFIG_DIR=$(mktemp -d)
trap 'rm -rf "$CLAUDE_CONFIG_DIR"' EXIT
fail=0

t() { # tool input expected
  local out got
  out=$(jq -cn --arg t "$1" --argjson ti "$2" '{tool_name:$t,tool_input:$ti}' \
    | PATH=/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin bash "$hook") || { echo "FAIL hook exit≠0: $2"; fail=1; return; }
  got=$(jq -r '.hookSpecificOutput.permissionDecision // "allow"' <<<"${out:-{\}}")
  if [[ "$got" == "$3" ]]; then printf 'ok   %-5s %-12s %s\n' "$3" "$1" "$2"
  else printf 'FAIL want=%-5s got=%-5s %-12s %s\n' "$3" "$got" "$1" "$2"; fail=1; fi
}

# Bash — deny
t Bash '{"command":"sudo apt install x"}' deny
t Bash '{"command":"chmod 777 file"}' deny
t Bash '{"command":"chmod -R 0777 dir"}' deny
t Bash '{"command":"chown -R 777 dir"}' deny
t Bash '{"command":"rm -rf /"}' deny
t Bash '{"command":"rm -rf /*"}' deny
t Bash '{"command":"rm -rf ~"}' deny
t Bash '{"command":"rm -rf ~/"}' deny
t Bash '{"command":"rm -rf $HOME"}' deny
t Bash '{"command":"rm -rf ${HOME}/"}' deny
t Bash '{"command":"rm -rf .git"}' deny
t Bash '{"command":"rm -fr .git/"}' deny
t Bash '{"command":"cd repo && rm -rf .git"}' deny
t Bash '{"command":"git add -A"}' deny
t Bash '{"command":"git add --all"}' deny
t Bash '{"command":"git add . && git commit -m x"}' deny
t Bash '{"command":"git add README.md ."}' deny
t Bash '{"command":"git -C sub add -A"}' deny
t Bash '{"command":"cd x; git add -A"}' deny
# Bash — ask
t Bash '{"command":"rm -rf build/"}' ask
t Bash '{"command":"rm -r tmpdir; ls"}' ask
t Bash '{"command":"rm -Rf ~/scratch/x"}' ask
t Bash '{"command":"rm --recursive out"}' ask
t Bash '{"command":"git push --force origin feat"}' ask
t Bash '{"command":"git push origin feat -f"}' ask
t Bash '{"command":"git push --force-with-lease"}' ask
t Bash '{"command":"git reset --hard HEAD~1"}' ask
t Bash '{"command":"git clean -fd"}' ask
t Bash '{"command":"git clean -xdf"}' ask
# Bash — allow
t Bash '{"command":"ls ~/sudoku"}' allow
t Bash '{"command":"chmod 644 file && echo 777"}' allow
t Bash '{"command":"chmod +x script.sh"}' allow
t Bash '{"command":"rm file.txt"}' allow
t Bash '{"command":"rm -f a b"}' allow
t Bash '{"command":"git rm -r --cached skills/x"}' allow
t Bash '{"command":"git add README.md"}' allow
t Bash '{"command":"git add ./scripts/x.sh"}' allow
t Bash '{"command":"git add -p src/"}' allow
t Bash '{"command":"git push -u origin feat"}' allow
t Bash '{"command":"git reset --soft HEAD~1"}' allow
t Bash '{"command":"grep -r foo ."}' allow
t Bash '{"command":"docker rm -f ctr"}' allow
t Bash '{"command":"npm rm -g pkg"}' allow
t Bash '{"command":"echo sudoers"}' allow
# Edit/Write — deny
t Write '{"file_path":"/repo/.env"}' deny
t Write '{"file_path":"/repo/.env.local"}' deny
t Edit '{"file_path":"/repo/.env.production"}' deny
t Edit '{"file_path":"/repo/.git/hooks/pre-commit"}' deny
t Edit '{"file_path":".git/config"}' deny
t MultiEdit '{"file_path":"/repo/node_modules/x/index.js"}' deny
# Edit/Write — allow
t Edit '{"file_path":"/repo/.env.example"}' allow
t Edit '{"file_path":"/repo/.env.sample"}' allow
t Edit '{"file_path":"/repo/.envrc"}' allow
t Edit '{"file_path":"/repo/config/environment.env.yaml"}' allow
t Edit '{"file_path":"/repo/.github/workflows/ci.yml"}' allow
t Edit '{"file_path":"/repo/.gitignore"}' allow
t NotebookEdit '{"notebook_path":"/repo/nb.ipynb"}' allow
# Other tools — never touched
t Read '{"file_path":"/repo/.env"}' allow
t Agent '{"prompt":"rm -rf /"}' allow

if [[ $fail -eq 0 ]]; then echo "all safety-guard cases pass"; else echo "safety-guard: FAILURES"; exit 1; fi
