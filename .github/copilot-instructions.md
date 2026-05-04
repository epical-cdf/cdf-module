# CDFModule — Project Guidelines

## Overview

PowerShell module for the Epical Cloud Deployment Framework (CDF). Supports Azure Container Apps, Function Apps, Logic Apps, APIM, Service Bus, and Postgres deployments with layered configuration (Platform → Application → Domain → Service).

## Way of Working

See [CONTRIBUTING.md](../CONTRIBUTING.md) for the full workflow. Summary:

1. **Issue first** — Create a GitHub issue before starting work
2. **Branch from issue** — Use `bugfix/<issue>-<short-desc>` or `feature/<issue>-<short-desc>`
3. **Conventional commits** — `feat:`, `fix:`, `docs:`, `refactor:`, `test:`, `chore:`
4. **Push and create PR** — Reference the issue with `Fixes #<number>` in the PR body
5. **Update CHANGELOG** — Add entry under `## [Unreleased]` in the PR
6. **Review → Approve → Merge → Delete branch**
7. **Tag pre-release** — `v1.x.y-pre` for CI/testing

### Release

1. Rename `[Unreleased]` to `[X.Y.Z] - YYYY-MM-DD` in CHANGELOG, add fresh `[Unreleased]`
2. Tag with `vX.Y.Z` — triggers the release workflow (publishes to PSGallery)

## Code Conventions

- **PowerShell 7.4+** (Core only)
- File naming: `func_<Verb>-<Noun>.ps1` — public in `CDFModule/Public/`, private in `CDFModule/Private/`
- All public functions get the `Cdf` prefix via `DefaultCommandPrefix` in the manifest
- Use `[CmdletBinding()]` and standard parameter attributes
- Run `Invoke-ScriptAnalyzer -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse -Fix` before committing
- Pester tests go alongside the function: `func_<Verb>-<Noun>.Tests.ps1`

## Architecture

- `CDFModule.psm1` — Auto-loads all `func_*.ps1` files recursively, exports Public functions
- `CDFModule.psd1` — Manifest; version is set by the release workflow from the git tag
- `Resources/` — Schemas, profiles, format files
- `samples/` — Reference settings and blank templates for all CDF layers
- `docs/` — [CDF Overview](../docs/README.md), [Infrastructure](../docs/infrastructure-development.md), [Solution](../docs/solution-development.md)

## Build and Test

```powershell
# Lint
Import-Module PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path ./CDFModule/ -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse

# Test
Invoke-Pester -Path ./CDFModule/ -Recurse

# Prepare release (lint + autofix)
./prepare-release.ps1
```

## Dependencies

- `Az.ResourceGraph` (required module)
- External: `Az`, `DnsClient-PS`, `ACME-PS`
