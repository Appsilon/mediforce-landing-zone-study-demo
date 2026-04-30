# Mediforce Landing Zone — Study Demo (CDISCPILOT01)

This repository holds the contract config for a single clinical-trial study consumed by the Mediforce Landing Zone workflow. It follows a **one-study-per-repo** pattern: each new study gets its own dedicated repository mirroring this one. Data managers manage the study contract via pull requests here, independently of the platform code.

## Layout

```
.
├── README.md
├── CODEOWNERS
├── .gitignore
├── .github/
│   └── PULL_REQUEST_TEMPLATE.md
├── config.yaml                          # The active study contract — edit via PR
├── validation-rules.yaml                # Custom edit checks (R + pointblank, layer 2)
└── templates/
    ├── study-config.template.yaml       # Scaffold for new studies
    ├── validation-rules.template.yaml   # Scaffold for custom edit checks
    └── cleaning-rule.template.yaml      # Placeholder (v0.2)
```

## How this fits the platform

`config.yaml` is the human-facing contract: study identity, expected delivery cadence, required SDTM/ADaM domains, contract timeline (key milestone dates), validation standard, router thresholds, and SFTP coordinates (placeholder host — real CRO host stays in workflow secrets, never in this repo). The Mediforce Landing Zone workflow definition (in the platform monorepo) points at this repository through its `workspace.remote` field; runtime scripts read configuration from environment variables injected by the workflow definition, not from this YAML.

For onboarding a new study, see the platform monorepo doc: [`docs/landing-zone-onboarding.md`](https://github.com/Appsilon/mediforce/blob/main/docs/landing-zone-onboarding.md).

## Two-layer validation

The landing zone runs two validation layers on every CRO delivery:

### Layer 1 — CDISC CORE (standard conformance)

The open-source CDISC rules engine checks whether datasets conform to SDTM/ADaM standards. ~1600 built-in rules maintained by CDISC. Configured via `config.yaml` fields: `validation.standard`, `validation.igVersion`, `validation.rulesets`.

### Layer 2 — Custom edit checks (R + pointblank)

Study-specific business rules defined in `validation-rules.yaml`. Executed by the `validate_custom.R` script (in the platform monorepo) using the [pointblank](https://rstudio.github.io/pointblank/) R package with [haven](https://haven.tidyverse.org/) for `.xpt` file I/O.

Data managers own this file. AI agents may propose rule changes via pull requests.

Available check types:

| Check | What it validates |
|-------|-------------------|
| `col_vals_in_set` | Variable values must be in a defined set |
| `col_vals_not_null` | Variable must not be null/NA |
| `col_vals_between` | Numeric variable within [left, right] |
| `rows_distinct` | Specified columns must be unique |
| `cross_domain_ref` | Referential integrity across domains (e.g. every USUBJID in AE must exist in DM) |

### Router thresholds

After both validation layers run, findings are classified into one of five classes: `clean`, `minor-fix`, `recovery`, `escalate`, `chaos`. The classification thresholds are configurable in `config.yaml` under `validation.routerThresholds`:

- `minorFixCtRatio` — ratio of Controlled Terminology findings to trigger minor-fix (default 0.80)
- `chaosCriticalStructureFraction` — fraction of expected domains with critical structure findings to trigger chaos (default 0.50)
- `defaultSeverity` — how to treat findings with missing severity (default Major)

## Contract timeline

`config.yaml` includes a `contract.timeline` block with key milestone dates:

| Field | Meaning |
|-------|---------|
| `enrollmentStart` | First Patient First Visit |
| `lastPatientLastVisit` | LPLV — last patient last visit |
| `databaseLock` | Hard deadline for final clean data |
| `submissionTarget` | Regulatory submission target date |
| `currentPhase` | `recruitment` / `mid` / `closeout` / `urgent` |

Agents use these dates for urgency context — for example, escalation behaviour changes as the study approaches database lock.

## v0.1 limitations

- Per-run audit trails (one branch per run, recording every script output and human verdict) accumulate **inside the platform host** in a local bare repo. They do **not** push to this remote in v0.1.
- The cleaning-rules-PR pattern (auto-generated PRs proposing deterministic value mappings such as `NY -> New York`) is a v0.2 deliverable. The `templates/cleaning-rule.template.yaml` file is a placeholder for that future shape.
