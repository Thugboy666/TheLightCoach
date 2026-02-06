# Codex Work Report

Use this exact format for every report.

## Files changed
- [ ] List files with short rationale.

## Diff summary
- [ ] Summarize key changes in 3-5 bullets.

## Tests run (+ output)
- [ ] Command + short output or note.

## How to run (comandi)
1. `./tools/context_pack.ps1`
2. `./tools/quick_test.ps1` (avvia e poi termina il server, quindi `netstat` potrebbe non mostrare `:8000` dopo l'esecuzione)
3. `& .\runtime\scripts\run_local.ps1`
4. `powershell -ExecutionPolicy Bypass -File .\runtime\scripts\run_local.ps1`

## Rollback plan
- [ ] Describe rollback steps (git reset --hard, restore runtime).
