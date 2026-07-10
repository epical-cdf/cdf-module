# CDF Template Scopes — Platform · Application · Domain · Service

CDF organizes infrastructure-as-code templates into **four nested scopes**. Each owns a distinct concern and composes with the others by **delegation, not duplication**. Together they carry a deployment from *pure infrastructure* up to a *running solution workload*.

| Scope | Concern | Typically owns |
|---|---|---|
| **Platform** | **Pure infrastructure** — the landing zone | subscription / resource-group layout, networking (hub-spoke, private endpoints), shared infrastructure DNS + solution DNS zones, platform Key Vault, platform identity, observability backbone |
| **Application** | **Application infrastructure** — a runtime *instance* | the runtime host (container-app managed environment, app-service plan, API management, …), application Key Vault, an application DNS sub-zone delegated from the platform (+ wildcard certificate), and the **application (environment) managed identity** |
| **Domain** | **Solution resources / trust boundary** — a management + RBAC grouping of microservices | domain Key Vault, **domain managed identity**, domain-scoped sub-resources (e.g. a delegated DNS sub-zone) and scoped RBAC. A CDF Domain is an *infrastructure grouping*, not a business solution. |
| **Service** | **Solution workload implementation runtime** — the deployable microservice | the workload itself (container app, function app, logic app, API definition), plus its service-specific configuration and bindings |

A request resolves **downward** — a workload runs inside a domain, inside an application instance, on a platform. Resources are provisioned **top-down by delegation** — the platform delegates to the application, which delegates to the domain, which the service consumes.

## Design principles

- **Delegation, not duplication.** Each scope derives from the one above — DNS zones delegate via NS records, RBAC is scoped per layer, certificate chains and resource names are derived from the parent context. A concern is owned at **exactly one** scope.
- **Scope-bound identities.** The runtime *environment* uses the **application** managed identity; *workloads* run as the **domain** managed identity (the trust boundary); deploy-time resource writes use the **deployment principal**. A practical consequence: an *environment-level* resource (e.g. a managed-environment certificate sourced from Key Vault) must use an identity **assigned to the environment** — the application identity — so **environment-shared** certificates/secrets belong in the **application** Key Vault, while **domain-scoped** application secrets belong in the **domain** Key Vault.
- **Opt-in and additive.** A scope's optional feature provisions only when its flag is set in configuration; absent ⇒ no-op, no cost. A consumer that does not opt in is unaffected.
- **Composition over configuration sprawl.** Because each scope contributes its own slice, an end-to-end capability (for example DNS-based service addressing) is assembled from small, single-concern pieces at each layer rather than one monolithic template.

## Relation to a business / solution catalog

This **infrastructure / template** layering is **orthogonal** to any **business / solution** catalog model (for example *Enterprise Service → Solution → Microservice* in a CMDB). A CDF **Domain** is an infrastructure and management grouping — it is **not** the business Solution. One Solution's microservices may span several Domains, and one Domain may host microservices from several Solutions. Keep the two models distinct.

## A worked example — DNS-based service addressing

DNS addressing is a clean illustration because it traverses **all four scopes**:

- **Platform** provisions the shared infrastructure-DNS and solution-DNS zones (and their wildcard certificates).
- **Application** delegates an application infrastructure-DNS sub-zone from the platform zone and binds its wildcard certificate (read via the application identity).
- **Domain** (opt-in) delegates its own infrastructure-DNS sub-zone (public for ACME validation, private for in-VNet resolution) and a domain wildcard certificate.
- **Service** declares the hostnames it needs; the template binds them as custom domains and writes the resolving records.

No single template "does DNS"; each scope contributes its layer, and the capability emerges from their composition — the defining characteristic of the model.
