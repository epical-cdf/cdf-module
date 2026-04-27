# Contributing to CDFModule

Thank you for contributing to the Epical Cloud Deployment Framework module.

## Prerequisites

- PowerShell 7.4+ (Core)
- [PSScriptAnalyzer](https://www.powershellgallery.com/packages/PSScriptAnalyzer) module
- [Pester](https://www.powershellgallery.com/packages/Pester) v5+ for tests
- [GitHub CLI](https://cli.github.com/) (`gh`) for issue/PR management

## Workflow

### 1. Create an Issue

Every change starts with a GitHub issue. Describe the bug, feature request, or improvement.

### 2. Create a Branch

Branch from `main` using the issue number:

```bash
git checkout main && git pull
git checkout -b bugfix/<issue>-<short-desc>   # for bug fixes
git checkout -b feature/<issue>-<short-desc>  # for features/enhancements
```

Examples: `bugfix/47-application-token-values`, `feature/49-flexible-service-config`

### 3. Make Changes

- **Public functions** go in `CDFModule/Public/func_<Verb>-<Noun>.ps1`
- **Private helpers** go in `CDFModule/Private/func_<Verb>-<Noun>.ps1`
- **Tests** go alongside: `func_<Verb>-<Noun>.Tests.ps1`
- **Schemas** go in `CDFModule/Resources/Schemas/`

Use `[CmdletBinding()]` and standard parameter attributes. All public functions receive the `Cdf` prefix automatically via the module manifest.

### 4. Lint

```powershell
Invoke-ScriptAnalyzer -Path ./CDFModule/ -Settings ./PSScriptAnalyzerSettings.psd1 -Recurse -Fix
```

### 5. Test

```powershell
Invoke-Pester -Path ./CDFModule/ -Recurse
```

### 6. Commit with Conventional Commits

```bash
git add <files>
git commit -m "feat: add package management commands

Fixes #51"
```

Prefixes:
| Prefix | Use for |
|--------|---------|
| `feat:` | New features or capabilities |
| `fix:` | Bug fixes |
| `docs:` | Documentation only |
| `refactor:` | Code changes that don't add features or fix bugs |
| `test:` | Adding or updating tests |
| `chore:` | Build, CI, tooling changes |

Reference the issue with `Fixes #<number>` in the commit body to auto-close on merge.

### 7. Push and Create a PR

```bash
git push -u origin <branch-name>
gh pr create --title "<prefix>: <description>" --body "Fixes #<number>" --base main
```

Use `--draft` for work-in-progress PRs that need discussion.

### 8. Update CHANGELOG

Add an entry under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md):

```markdown
## [Unreleased]

### Added
- Description of new feature (PR #XX)

### Fixed
- Description of bug fix (PR #XX)

### Changed
- Description of change (PR #XX)
```

Categories follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/): Added, Changed, Deprecated, Removed, Fixed, Security.

### 9. Review and Merge

- Request review from a team member
- Address feedback
- On approval: **Squash and merge** (keeps main history clean)
- Delete the branch after merge

### 10. Pre-release Tag (optional)

For CI/testing before a full release:

```bash
git tag v1.x.y-pre
git push --tags
```

## Release Process

1. Create a PR that updates the CHANGELOG:
   - Rename `## [Unreleased]` to `## [X.Y.Z] - YYYY-MM-DD`
   - Add a fresh `## [Unreleased]` section at the top
2. Merge the PR
3. Tag and push the release:
   ```bash
   git tag vX.Y.Z
   git push --tags
   ```
4. The [release workflow](.github/workflows/release-cdfmodule.yaml) automatically:
   - Sets the module version from the tag
   - Publishes to PSGallery
   - Creates a GitHub release with the module zip

## Project Structure

```
CDFModule/
├── CDFModule.psd1          # Module manifest (version set by CI)
├── CDFModule.psm1          # Auto-loads func_*.ps1, exports Public/
├── Public/                 # Exported functions (get Cdf prefix)
│   ├── func_Get-Config.ps1
│   └── func_Get-Config.Tests.ps1
├── Private/                # Internal helpers (not exported)
└── Resources/              # Schemas, profiles, format files
docs/                       # Documentation
samples/                    # Reference configs and templates
```
