# USWAG: Unified System for Work and Growth
**Project Proposal · Advanced Relational Database Systems (Final Project)**
Proponents: Bryan Jay Lumabas and Claire Pillo · © 2026 Bryan Jay Lumabas and Claire Pillo

The database is the project. The website only presents it.

## What is inside (one flat folder, no sub-folders)
| File | Contents |
|---|---|
| `uswag_db.sql` | Final MySQL / MariaDB script: 12 tables, 9 views, 18 procedures, 26 triggers, sample data and 14 queries. |
| `uswag_erd.mmd`, `uswag_erd_crowsfoot.svg`, `uswag_erd_crowsfoot.png` | Crow’s Foot ERD: Mermaid source and the saved drawings (same source). |
| `USWAG_Business_Rules.pdf`, `USWAG_Normalization_Proofs.pdf`, `USWAG_Performance_Report.pdf` | The three written documents. Their Markdown sources are `uswag_business_rules.md`, `uswag_normalization_proof.md` and `uswag_performance_report.md`. |
| `USWAG_Project_Proposal.docx`, `USWAG_Project_Proposal.pdf`, `USWAG_Slides_Plain.pptx`, `USWAG_Slides_Interface.pptx` | The presentation (all 16:9). |
| `01_phase1-proposal_s1.png` to `15_phase5-deliverables_s1.png` | Interface screenshots used by the slides. |
| `index.html` | The dedication, the entry page. |
| `phase1-proposal.html` to `phase5-deliverables.html` | The five phase pages. |
| `styles.css`, `script.js`, `theme.js`, `data.js` | Design, behavior, dark-mode switch and embedded content. |
| `uswag.png`, `im1.png`, `slp.png`, `dswd.png` | Logos. |

## How to run
1. **Database:** start Laragon, open HeidiSQL, choose *File > Run SQL file* and pick `uswag_db.sql`. Or run `mysql -uroot < uswag_db.sql`. The script drops and recreates `uswag_db`.
2. **Website:** unzip everything into one folder and open `index.html` in a browser. The ERD needs internet to draw live; offline it shows the saved SVG.
3. **Present:** press **▶ Present** (or the P key). Arrow keys move between slides and phases, Esc exits.
4. **Dark mode:** use the switch at the bottom left of Phase 1. The choice is remembered.
5. **Print:** Ctrl+P prints one 16:9 slide per page. Turn on *Background graphics* for the best result.
6. **Dedication:** the gold button at the bottom of Phase 5 opens `index.html`.

## Database notes
- The database enforces every rule, so any frontend can change without touching the script.
- Capital can change only through the ledger (`sp_capital_move`).
- Tested on MariaDB 10.11: imports with 0 errors, 12 tables, 9 views, 18 procedures, 26 triggers. Demo flow: capital 5,000 + sales 2,600 − expense 1,500 = 6,100; stock 500 → 450.
- Index test (50,000 sales / 100,000 lines): 146 ms → 2.5 ms.
- Known limit: registration leaves `Sellers.first_name` and `last_name` unfilled, so some reports show the username.

## Deploy (GitHub Pages or Cloudflare Pages)
- Put all files in the root of the repository. Keep them together; nothing is in a sub-folder.
- Cloudflare Pages: build command empty, output directory `/` (the root).
- GitHub Pages: publish the repository root. `.nojekyll` is included.
- All links are relative and point to files in the same folder.
