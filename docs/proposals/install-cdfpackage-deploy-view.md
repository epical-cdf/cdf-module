# Proposal: complete the package deploy-from-cache path (`Install-CdfPackage` → `Deploy-CdfTemplate*`)

**Status:** Draft for the CDFModule build team · **Affects:** CDFModule ≥ 1.2.22 (package commands:
`Publish-CdfTemplate`, `Publish-CdfConfig`, `Install-CdfPackage`, `Get-CdfPackage`)
**Author:** Andreas Stenlund · **Discovered in:** `axl-it-ops/axl-lz-db` (db01 DBaaS landing zone), first real adopter of the OCI publish/install flow.

## 1. Summary

The new package commands **publish and install correctly**, but the **deploy-from-cache path is
incomplete**: after `Install-CdfPackage`, the environment variables it sets (`CDF_INFRA_TEMPLATES_PATH`,
`CDF_INFRA_SOURCE_PATH`) point at cache directories whose **layout does not match what the existing
`Get-Cdf*Config*` / `Deploy-CdfTemplate*` loaders expect**. As a result, a clean
`Install-CdfPackage` → `Deploy-CdfTemplatePlatform` fails.

**Ask:** make `Install-CdfPackage` materialise a **classic-layout deploy view** in the cache and point
`CDF_INFRA_*` at *that*, so the existing deploy cmdlets work unchanged. (Alternatives in §6.)

## 2. Context — the intended workflow

The package model replaces "point `CDF_INFRA_*` at the working tree / a release zip" with:

```
Publish-CdfTemplate / Publish-CdfConfig   # CI: pack template/config dirs → OCI artifacts in a registry
Install-CdfPackage                         # local/CI: pull declared packages to ~/.cdf, set CDF_INFRA_*
Get-CdfConfigPlatform | Deploy-CdfTemplatePlatform   # deploy from the cached release
```

This is the workflow we want for landing-zone deploys (released, versioned templates + configs, not the
working tree). The publish + install halves work; the deploy half does not.

## 3. What works

- `Publish-CdfTemplate` / `Publish-CdfConfig` → `oras push` to `ghcr.io/<org>` (OCI provider,
  `GITHUB_TOKEN`). Verified: 5 packages published to `ghcr.io/axl-it-ops:0.1.0`.
- `Install-CdfPackage` reads `cdf-packages.json`, resolves semver ranges, `oras pull`s to the cache,
  and `Test-Dependency` passes.
- Registry resolution layering (`.cdf/registries/<name>.json` project → user → inline) works — note it
  means a **personal `~/.cdf/registries/default.json` silently overrides** a repo's inline `default`
  (we hit this; a project-level `.cdf/registries/default.json` is the fix, but it's a sharp edge worth
  documenting).

## 4. Reproduction

```pwsh
# Given a repo with cdf-template.json/cdf-runtime.json manifests + cdf-packages.json (default → ghcr.io/axl-it-ops)
$env:GITHUB_TOKEN = gh auth token
Install-CdfPackage          # downloads to ~/.cdf, sets CDF_INFRA_TEMPLATES_PATH + CDF_INFRA_SOURCE_PATH
$env:CDF_PLATFORM_ID='axldb'; $env:CDF_PLATFORM_INSTANCE='01'; $env:CDF_PLATFORM_ENV_ID='axl-dev'; $env:CDF_REGION='swedencentral'
Get-CdfConfigPlatform | Deploy-CdfTemplatePlatform
```

Result:

```
Cannot find path '…/.cdf/packages/configs/ghcr.io/axl-it-ops/axldb01/0.1.0/axldb/01/platform/environments.json'
because it does not exist.
```

## 5. Root cause — cache layout vs. classic loader layout

`Install-CdfPackage` sets (see `func_Install-Package.ps1`, the block commented *"Set environment
variables for backwards compatibility"*):

- `CDF_INFRA_TEMPLATES_PATH = <cacheRoot>/templates/<endpoint>`
- `CDF_INFRA_SOURCE_PATH    = <cacheRoot>/configs/<endpoint>/<configPath>/<release>`

The cache stores (see `func_CdfPackageCache.ps1`): `~/.cdf/packages/{templates|configs}/<endpoint>/<path>/<release>/…`

But the deploy loaders resolve:

| Loader resolves | Cache actually provides | Mismatch |
|---|---|---|
| `$CDF_INFRA_TEMPLATES_PATH/<scope>/<name>/<version>/` | `…/<endpoint>/<scope>/<name>/<version>/`**`<release>`**`/` | extra `/<release>/` level |
| `$CDF_INFRA_SOURCE_PATH/<platformId>/<instanceId>/…` | `…/<endpoint>/`**`<configKey>/<release>`**`/<flattened-instance-contents>` | config is flattened to the instance contents; the loader re-appends `<platformId>/<instanceId>` → double-nest / not found |

So the env-var bridge points "one level too high" for templates and at the flattened-instance dir for
configs, neither of which the loaders understand.

**Reconstruction also exposes a second issue.** Building a symlinked classic-layout view
(`<view>/<scope>/<name>/<version>` → release dir; `<view>/<platformId>/<instanceId>` → config release
dir) gets *past* the path error, but `Get-CdfConfigPlatform` then returns a **partial config**
(`templateName` / `region` empty) and `Deploy-CdfTemplatePlatform` fails with *"Cannot bind argument to
parameter 'Path' because it is null"*. Cause: the loader `Resolve-Path`s the symlink back to the flat
cache dir and re-appends `<platformId>/<instanceId>`, so a **symlinked** view isn't enough — the view
must be real directories (copies/junctions) or the loaders must stop canonicalising.

## 6. Proposed solution

**Primary — `Install-CdfPackage` materialises a real classic-layout deploy view and points `CDF_INFRA_*` at it.**

After downloading packages, build a per-install view under the cache, e.g.:

```
~/.cdf/packages/.views/<hash>/templates/<scope>/<name>/<version>/   → contents of <templates>/<endpoint>/<scope>/<name>/<version>/<resolved-release>/
~/.cdf/packages/.views/<hash>/source/<platformId>/<instanceId>/     → contents of <configs>/<endpoint>/<configKey>/<resolved-release>/
```

then set:

```
CDF_INFRA_TEMPLATES_PATH = ~/.cdf/packages/.views/<hash>/templates
CDF_INFRA_SOURCE_PATH    = ~/.cdf/packages/.views/<hash>/source
```

- Use **real directories** — directory junctions/hardlinks where supported, else copy. Avoid symlinks
  (loaders `Resolve-Path`-canonicalise them, defeating the view — see §5).
- Split `<configKey>` → `<platformId>/<instanceId>` using the same rule `Publish-CdfConfig` used to
  build it (`platformId + instanceId`), or carry `platformId`/`instanceId` in the cache index so the
  view builder doesn't have to re-parse.
- Cross-platform: Windows directory junctions (`New-Item -ItemType Junction`) / `mklink /J`; macOS/Linux
  bind-style isn't available without root, so **copy** is the safe default (template/config dirs are small).

This keeps `Get-Cdf*`/`Deploy-Cdf*` **unchanged** — the smallest blast radius.

**Alternatives considered**

1. *Make the loaders package/cache-aware* (descend into the resolved release; map `<platformId>/<instanceId>` → `<configKey>/<release>`). More invasive, touches the hot deploy path, higher regression risk.
2. *Change the cache layout to be deploy-shaped* (drop the `<release>` leaf, nest configs under `<platformId>/<instanceId>`). Breaks multi-release caching and `Get-CdfPackage`/index semantics.

The view approach (primary) is preferred: localised to `Install-CdfPackage`, leaves cache + loaders intact.

## 7. Acceptance criteria

- `Install-CdfPackage` then `Get-CdfConfigPlatform | Deploy-CdfTemplatePlatform` (and `…Application` /
  `…Domain`) **succeeds from the cache**, with a fully-populated config (`templateName`, `templateVersion`,
  `region`, …) — no working-tree paths set by the user.
- Works for multiple cached releases of the same package (view reflects the resolved range).
- Works cross-platform (Linux CI runner + macOS/Windows workstation).
- `README` quick-start `Install-CdfPackage` → deploy works verbatim.

## 8. Notes

- **Registry override sharp edge** (§3): consider logging which registry source won
  (`project | user | inline`) at `Install`/`Publish` time, so a personal `~/.cdf/registries/default.json`
  silently redirecting an org repo is visible. We worked around it with a committed project-level
  `.cdf/registries/default.json`.
- **`cdf-packages.json` `configs` vs `settings`**: the installed/fork `Install-Package` reads
  `$manifest.configs`, but the `cdf-infra-main` reference manifest uses a `settings` key — these don't
  match (configs silently not installed if `settings` is used). Align the schema + the reference.

## Appendix — environment

- CDFModule 1.2.22(-pre); `oras` 1.3.2; OCI provider → `ghcr.io/axl-it-ops`, `GITHUB_TOKEN`.
- Worked example: `axl-it-ops/axl-lz-db`, packages `cdf/templates/{platform/dataplatform,application/mssql,domain/mssql}/v1net:0.1.0` and `cdf/configs/{axldb01,axcdb01}:0.1.0`.
- Cache root `~/.cdf/packages`; layout `{templates|configs}/<endpoint>/<path>/<release>/`.
