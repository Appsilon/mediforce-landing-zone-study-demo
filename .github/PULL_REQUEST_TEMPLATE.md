# Study config change

## Summary

<!-- One or two lines: what is changing and why. -->

## Change type

<!-- Check all that apply -->
- [ ] Contract timeline update
- [ ] Delivery schedule change
- [ ] Validation rule change (validation-rules.yaml)
- [ ] Router threshold change
- [ ] R validation script change (validate_custom.R)
- [ ] Other config change

## Reviewer checklist

- [ ] Study ID in `config.yaml` is correct and matches the repository name
- [ ] `config.yaml` parses as valid YAML (no tab/indent issues, no unquoted special characters)
- [ ] `contract.expectedDeliveries[].cadence` and `day` make schedule sense (e.g. `weekly` + `monday`, `monthly` + a day-of-month integer)
- [ ] `contract.timeline` dates are consistent (enrollmentStart < LPLV < databaseLock < submissionTarget)
- [ ] Required domains list matches the SDTM/ADaM standard for the current study phase
- [ ] No CRO secrets (real SFTP host, credentials) committed — those belong in workflow secrets
- [ ] Validation rules in `validation-rules.yaml` use correct check function names and valid severity levels
- [ ] Router thresholds are within reasonable ranges (ratios between 0 and 1)
- [ ] Reviewer (data manager) has eyeballed the change against the protocol
