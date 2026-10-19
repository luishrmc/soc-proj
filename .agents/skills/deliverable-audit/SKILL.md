---
name: deliverable-audit
description: Audits final course deliverables against utils/plan/Checklist_de_Entregaveis.csv, verifies repository hygiene, and packages the final deliverable archive.
---

# Deliverable Audit Skill

Verifies that all required artifacts for the university course deliverable exist, are properly formatted, free of secrets or machine-specific paths, and conform to `utils/plan/Checklist_de_Entregaveis.csv`.

## 1. When to Use
- Auditing workspace completion during Phase 6.
- Generating the final delivery `.zip` package (Task 6.3).
- Updating `Status de Conformidade` in `Checklist_de_Entregaveis.csv`.

## 2. Deliverable Checklist Audit Items

| Deliverable Item | Required Format | Expected Workspace Path |
|---|---|---|
| **Fontes VHDL** | `.vhdl` | `cora7z/app/hw/src/*.vhdl` |
| **Testbenches** | `tb_*.vhdl` | `cora7z/app/hw/test/tb_*.vhdl` |
| **Código C/C++** | `.c`, `.cpp`, `.h` | `cora7z/app/sw/src/` and `esp32/` |
| **Diagrama de Blocos** | `.png` or `.jpg` | `docs/diagrams/block_diagram.png` |
| **Relatório Final** | `.pdf` | `docs/report/relatorio_final.pdf` |
| **Repositório GitHub** | Public URL | Documented in `README.md` |

## 3. Hygiene & Portability Verification
Before bundling the final package, verify:
1. **No Absolute Paths**: Search for machine-specific path prefixes (`/home/<user>/...`) in committed files.
2. **No Build Bloat**: Ensure `build/`, `.venv/`, `.Xil/`, `*.jou`, `*.log`, and `*.xpr` are not bundled.
3. **Reproducibility**: Ensure `cora7z/app/hw/Makefile` and `cora7z/app/hw/run.py` run cleanly from a fresh checkout.

## 4. Packaging Command
```bash
# Package the clean deliverable archive
zip -r out/entrega_cora_z7_compress_crypto.zip \
    cora7z/ docs/ esp32/ utils/ .agents/ \
    README.md requirements.txt .gitignore \
    -x "*.venv*" "*build*" "*out*" "*__pycache__*" "*.git*" "*vivado/*.runs*"
```
