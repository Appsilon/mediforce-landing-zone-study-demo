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
└── templates/
    ├── study-config.template.yaml       # Scaffold for new studies
    └── cleaning-rule.template.yaml      # Placeholder (v0.2)
```

## How this fits the platform

`config.yaml` is the human-facing contract: study identity, expected delivery cadence, required SDTM/ADaM domains, validation standard, SFTP coordinates (placeholder host — real CRO host stays in workflow secrets, never in this repo). The Mediforce Landing Zone workflow definition (in the platform monorepo) points at this repository through its `workspace.remote` field; runtime scripts read configuration from environment variables injected by the workflow definition, not from this YAML.

For onboarding a new study, see the platform monorepo doc: [`docs/landing-zone-onboarding.md`](https://github.com/Appsilon/mediforce/blob/main/docs/landing-zone-onboarding.md).

## v0.1 limitations

- Per-run audit trails (one branch per run, recording every script output and human verdict) accumulate **inside the platform host** in a local bare repo. They do **not** push to this remote in v0.1.
- The cleaning-rules-PR pattern (auto-generated PRs proposing deterministic value mappings such as `NY -> New York`) is a v0.2 deliverable. The `templates/cleaning-rule.template.yaml` file is a placeholder for that future shape.
