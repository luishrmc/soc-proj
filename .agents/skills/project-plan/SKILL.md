---
name: project-plan
description: Governs project management over utils/plan/ (Cronograma_e_Tarefas, Riscos_e_Bloqueios, Matriz_de_Testes_e_Métricas, Checklist_de_Entregaveis) via plan-sync.py.
---

# Project Plan Skill

This skill enforces deterministic project management for the course deliverables and tasks, ensuring synchronization between task status, dependencies, gate evidence, and risks.

## 1. When to Use
- Exclusively used by `orchestrator-agent` to query eligible tasks, transition task states, and record evidence.
- When validating the DAG integrity (no cycles, valid IDs).
- When recording new project risks or mitigations in `Riscos_e_Bloqueios.csv`.

## 2. Plan Files Architecture

All files are located in `utils/plan/`:
- `Cronograma_e_Tarefas.csv`: Master task schedule with 25 tasks across 6 phases.
  - Base columns (Portuguese deliverable format): `ID da Tarefa,Fase,Atividade Detalhada,Entregável Associado,Duração Estimada (dias),Dependências,Status,Prioridade`
  - Extended tracking columns: `Início,Fim,Evidência,Atualizado em,Notas`
- `STATUS.md`: Machine-generated summary (progress by phase, critical path, open blockers, next eligible tasks). **Do not edit manually**.
- `CHANGELOG.md`: Append-only audit trail recording every state change with timestamp and evidence.
- `Riscos_e_Bloqueios.csv`: Risk register tracking potential failure modes and mitigations.
- `Matriz_de_Testes_e_Métricas.csv`: 12-row experimental evaluation matrix.
- `Checklist_de_Entregaveis.csv`: Formal deliverable checklist.

## 3. Allowed Task States & Transitions

States:
- `Pendente`: Task waiting for prerequisites or start.
- `Em andamento`: Work currently active. Requires all dependencies to be `Concluída`.
- `Pendente de validação`: Code written and local gates pass, but missing hardware validation or blocked by skipped tool.
- `Concluída`: Fully completed with verified evidence (`gate:<task>` in `out/gates/<task>.json`).
- `Bloqueada`: Work stopped due to repeated failures (loop guard exit 70/71) or hardware blocker.

Transition graph:
```
Pendente ──> Em andamento ──> Concluída
   │              │                 │
   └──> Bloqueada <──> Pendente de validação
```

## 4. Canonical Commands

```bash
# Check validity of schedule and risks
python3 .agents/hooks/plan-sync.py check

# List tasks that are currently unblocked and eligible to start
python3 .agents/hooks/plan-sync.py next

# Start a task
python3 .agents/hooks/plan-sync.py set 2.1 "Em andamento" --notes "Starting SPI receiver implementation"

# Complete a task with gate evidence
python3 .agents/hooks/plan-sync.py set 2.1 "Concluída" --evidence gate:2.1 --notes "All gates passed"

# Regenerate STATUS.md, CHANGELOG.md, and internal state
python3 .agents/hooks/plan-sync.py sync
```

## 5. Negative Constraints
- Never manually edit `utils/plan/Cronograma_e_Tarefas.csv` with raw file editors; always use `plan-sync.py`.
- Never transition a task to `Concluída` without valid gate evidence recorded in `out/gates/<task>.json`.
- Never reorder or remove existing columns from the deliverable CSV files.
