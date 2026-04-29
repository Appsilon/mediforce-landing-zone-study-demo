# Study config change

## Summary

<!-- One or two lines: what is changing in config.yaml and why. -->

## Reviewer checklist

- [ ] Study ID in `config.yaml` is correct and matches the repository name
- [ ] `config.yaml` parses as valid YAML (no tab/indent issues, no unquoted special characters)
- [ ] `contract.expectedDeliveries[].cadence` and `day` make schedule sense (e.g. `weekly` + `monday`, `monthly` + a day-of-month integer)
- [ ] Required domains list matches the SDTM/ADaM standard for the current study phase
- [ ] No CRO secrets (real SFTP host, credentials) committed — those belong in workflow secrets
- [ ] Reviewer (data manager) has eyeballed the change against the protocol
