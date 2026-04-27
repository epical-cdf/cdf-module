# Changelog

All notable changes to the **CDFModule** will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- Container apps env vars with both SecretRef and Value properties (PR #46, 2025-11-07)

## [1.2.0] - 2025-10-06

> Tags: v1.2.13-pre through v1.2.19-pre span the changes below.

### Added

- Feature service config file – load service configuration from file (PR #45)
- Service config from file and params (PR #43)
- Functions for creating and updating function app service (PR #44)
- Save filtered config – fetch based on key wildcard (PR #42)
- Generalize API template build (PR #40)
- Option to export ARM params file (PR #39)
- Environment configuration in external config store (PR #32)
- Changes for creating schema for postgres service (PR #34)
- Postgres port property (PR #33)

### Fixed

- Assignment from wrong variable in solution deployer (PR #41)
- Key Vault identifier naming convention in cdf-secrets (PR #37)
- Bugfix cdf config service and connections – missing azure context, missing ServiceSrcPath (PR #38)
- Bugfix for Import-CdfApimPortalConfig (PR #36)

## [1.1.2] - 2025-06-02

> Tags: v1.2.5-pre through v1.2.10-pre span the changes below.

### Added

- Function app refactoring for node and .NET deployment (PR #31)
- Feature env config 1.2 (PR #30)
- Functionality for enabling Postgres Server at Platform and Domain Level (PR #29)
- Update containerapps config on deploy (PR #28)
- Update containerapp configuration and deployment command (PR #27)
- Config alignment and fixes – cert generation, containerapp- prefix (PR #26)
- Improved service configuration – service config object replaces params (PR #25)
- Update GitHub matrix deployer properties (PR #24)
- Fetch domain config from file (PR #21)
- Refactor azure context command – telemetry opt-out (PR #20)

### Fixed

- Error when no domain config (PR #23)
- Bug fix for service env vars override from app.settings.json (PR #19)
- Bugfix api overwrite secret (PR #18)
- Bug fix Deploy-Service (PR #17)
- Upgrade workflow artifact action (v1.2.4-pre)

## [1.1.0] - 2024-12-16

> Tags: v1.1.78-pre through v1.1.86-pre span the pre-release development.

### Added

- Service configuration feature (PR #16)
- Zip include hidden files support (PR #14, #15)
- Functions-Service config related changes (PR #12)
- Functions for importing GitHub secrets into Key Vault (PR #3)
- Update container environment properties for build context (PR #1)

### Fixed

- Bugfix APIM removal (PR #10)
- Add missing applicationId for applicationKey (PR #9)
- Bugfix keyvault secrets (PR #5, #6)
- Bugfix: external settings for containers (PR #4)
- Remove default prerelease tag from module definition
- Ensure releases don't have pre-release string
- Force push of release over pre-release

### Changed

- Function app settings – commented out deployment package related settings (PR #13)
- Use PSScriptAnalyzer for code quality
- Update release workflows to publish module

## [1.0.0] - 2024-08-14

### Added

- Initial import of CDFModule version 1.1.78-pre from internal development.
- PowerShell module for Epical Cloud Deployment Framework.
- Support for Azure Container Apps, Function Apps, Logic Apps, APIM, and Service Bus deployments.
- Configuration management for platform, application, domain, and service layers.
- GitHub Actions workflow integration.
