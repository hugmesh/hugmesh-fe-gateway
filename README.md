# snapdragon-fe-gateway

The **frontend front door** of a Snapdragon brand: the per-node-type instance of
the shared [snapdragon-gateway](https://github.com/Snapdragon-Systems/snapdragon-gateway)
Spring Cloud Gateway, deployed into the **frontend tier** to sit in front of the
web host shell and its module-federation remotes (`snapdragon.systems` host +
remotes).

It is **not its own service codebase**. It is a thin **overlay** that re-uses the
audited `snapdragon-gateway` image and changes only three things:

1. its **identity** — `SPRING_APPLICATION_NAME=snapdragon-fe-gateway`;
2. its **route set** — a single catch-all `Path=/**` route to the web frontend;
3. its **downstream URI** — the in-cluster frontend web service.

Everything else (the OAuth2 resource-server, the JWT→authority conversion, the
domain-scoping, the per-gateway route-access enforcement, revocation) is
**inherited unchanged** from the shared gateway image, so every device runs
identical, audited gateway code regardless of node type.

```bash
# GATEWAY_IMAGE must point at the sibling snapdragon-gateway image (CI passes the
# same-namespace tag automatically; see .gitlab-ci.yml). Default build-arg is
# snapdragon-systems/gateway:dev.
docker build -t snapdragon-systems/fe-gateway:dev .
```

---

## Where it sits

| | |
|---|---|
| **Tier** | frontend (host + remotes front door) |
| **Namespace** | `snapdragon-frontend` |
| **Identity** | `snapdragon-fe-gateway` (the `gateway` key for its route-access rows) |
| **Downstream** | `snapdragon-systems-web.snapdragon-frontend.svc.cluster.local:80` (override `DOWNSTREAM_URI`) |
| **Auth** | validates the **internal Casdoor JWT** as an OAuth2 resource server; **no external login is exposed** |
| **Base image** | `snapdragon-gateway` (one image, differentiated by `SPRING_APPLICATION_NAME`) |

A brand typically runs several gateway INSTANCES off this one image —
`snapdragon-fe-gateway` (this repo, the host + remotes front door),
`snapdragon-be-gateway` (backend / API + social homeservers), and
`snapdragon-pki-gateway` (identity: Casdoor + headscale) — each with its own
name, route set and route-access rows. This repo is the frontend one.

### What's in this repo

| File | Purpose |
|------|---------|
| `Dockerfile` | `FROM ${GATEWAY_IMAGE}` then bakes the fe identity + config + Liquibase changelog onto the shared image (sets `SPRING_APPLICATION_NAME` and `SPRING_CONFIG_ADDITIONAL_LOCATION`) |
| `application-fe.yml` | overlay config: `application.name`, the Casdoor `issuer-uri`, and the single `fe-default` `Path=/**` route to the web frontend |
| `liquibase/changelog/001-gateway-routes.xml` | seeds the `fe-default` route (`Path=/**` → `snapdragon-systems-web`) into the DB-backed `gateway_routes` registry |
| `liquibase/changelog/db.changelog-master.xml` | Liquibase master changelog that includes the route seed |
| `.gitlab-ci.yml` | builds + pushes this overlay image, basing the build off the sibling `snapdragon-gateway` image in the same in-cluster GitLab registry namespace |

CI is **GitLab** (in-cluster). There are no GitHub Actions workflows in this repo.

---

## Inherited capabilities (from `snapdragon-gateway`)

Because the image is the shared gateway, the fe-gateway gets the full gateway
authorization stack for free. The relevant pieces for the frontend front door:

### Casdoor resource server + role authorities

Every request must carry a valid internal Casdoor JWT (issuer `CASDOOR_ISSUER_URI`,
default `https://id.snapdragon.systems`). The shared `CasdoorAuthorities` converter
maps the token to Spring authorities:

- a `ROLE_USER` floor on every authenticated principal;
- `roles` claim → `ROLE_<UPPER>` (handles Casdoor's string-or-object role shape);
- `permissions` claim → verbatim authorities, **except** any entry beginning with a
  reserved prefix (`ROLE_` / `DOMAIN_`) is dropped — authority-injection defense;
- legacy `isAdmin: true` → `ROLE_ADMIN`;
- exactly one issuer-derived `DOMAIN_<x>` authority, keyed on the
  cryptographically-validated `iss` (never a user-settable claim).

The least-privilege cascade is `SUPERADMIN > ADMIN`/`MOD`/`USER`, plus the separate
`ROLE_IMAGE_BUILDER` capability.

### Domain scoping (multi-tenancy)

> Status: the issuer-keyed domain-scoping described here lands with the shared
> gateway's `feat/domain-foundation` work (`CasdoorAuthorities` /
> `DomainRegistry` / `Roles` / `GatewayRouteAccessFilter`). This overlay carries
> no source of its own and picks it up automatically from the base image.

`DomainRegistry` resolves the validated issuer → brand/domain. It is **opt-in and
backward-compatible**: with `APP_TENANCY_ISSUERS` unset, the lone configured issuer
maps to `DOMAIN_default` and a single-issuer cluster behaves exactly as before. When
populated, only listed per-brand Casdoors are trusted and an unknown `iss` **fails
closed (401)**. The `GatewayRouteAccessFilter` then **hard-denies** any
non-`SUPERADMIN` principal whose own domain — derived from the cryptographically
**validated issuer** (not from a spoofable authority entry) — does not match the
request's target domain, closing the cross-tenant hole before the grant layer is
even consulted. `ROLE_SUPERADMIN` is the **only** cross-domain bypass (the infra
control plane).

### Authorization filter chain

The shared WebFilters run (after Spring Security authenticates the JWT) in order:

| Order | Filter | Role in front of the web host |
|------:|--------|-------------------------------|
| +100 | `RevocationGatewayFilter` | reject revoked Casdoor tokens (Cassandra-cached) |
| +200 | `ExternalAuthHeaderFilter` | inject additive `External-Authorization` headers when an external-OAuth token is present (never required) |
| +250 | `GatewayRouteAccessFilter` | **per-gateway external-access rules** + the cross-domain hard-deny / `SUPERADMIN` bypass |
| +300 | `ResourceAccessFilter` | snapdragon.games per-resource grants (`game:{slug}`, `session:{id}`) |

`ROLE_ADMIN` / `ROLE_GAME-MASTER` on the internal JWT bypass the access filters
**within their own domain**, so the admin who manages the rules is never locked out.
Infra/observability paths (`/actuator/**`, …) stay gated to `GAME-MASTER` / `ADMIN` /
`SUPERADMIN` by the shared `SecurityConfig`.

### Per-gateway route access

`GatewayRouteAccessService` enforces the admin-managed "which roles/users may reach
which URLs from outside **this** gateway" rules. **Postgres is the source of truth**
(`ROUTE_ACCESS_R2DBC_URL`); the pod loads the `gateway_route_access` rows for its own
`spring.application.name` (= `snapdragon-fe-gateway`), write-through-mirrors them into
the Cassandra read-cache, and refreshes every tick. If Postgres is briefly
unreachable it serves the last-known Cassandra rows; if neither is configured it falls
back to the baked-in canonical seed — **never silently fail-open**. The admin-bff
(`snapdragon-admin-bff-api`) CRUDs the canonical rows. Longest-matching `url_pattern`
wins; explicit `allow=false` denies; the `PUBLIC` sentinel permits anonymous traffic.

---

## Configuration

Overlay-relevant env vars (the full set is documented in `snapdragon-gateway`):

| Env var | Default | Purpose |
|---------|---------|---------|
| `SPRING_APPLICATION_NAME` | `snapdragon-fe-gateway` | gateway identity + route-access `gateway` key (baked into the image) |
| `CASDOOR_ISSUER_URI` | `https://id.snapdragon.systems` | trusted Casdoor issuer for JWT validation |
| `DOWNSTREAM_URI` | `http://snapdragon-systems-web.snapdragon-frontend.svc.cluster.local:80` | the web frontend this gateway fronts |
| `APP_TENANCY_ISSUERS` | _(empty)_ | CSV `issuerUri=domain,…` — enables multi-brand mode (empty ⇒ single-tenant `default`) |
| `APP_TENANCY_HOSTS` | _(empty)_ | CSV `hostSuffix=domain,…` — defense-in-depth Host→domain map |
| `ROUTE_ACCESS_R2DBC_URL` | _(empty)_ | Postgres source-of-truth for route-access rows (empty ⇒ Cassandra-cache/seed only) |

---

## TODO: Anubis bot-challenge layer

[Anubis](https://anubis.techaro.lol/) is a proof-of-work HTTP challenge middleware designed to
block AI scrapers, credential-stuffers, and brute-force bots before they reach any upstream
service. The plan is to insert it as a transparent reverse proxy in front of this gateway so
suspicious traffic is challenged at the edge, not inside the JWT-validated gateway stack.

### Architecture

```
  Browser / client
        │
        ▼
  Anubis  (proof-of-work challenge, IP/UA heuristics)
        │  (challenged requests get a JS PoW puzzle; bots fail + get 429)
        │  (trusted requests forwarded immediately)
        ▼
  snapdragon-fe-gateway  (JWT validation, route-access enforcement)
        │
        ▼
  snapdragon-systems-web  (host shell)
```

Anubis runs as a sidecar container in the same `snapdragon-frontend` namespace, so the
fe-gateway's TCP port is never exposed directly to the cluster ingress.

### Implementation checklist

- [ ] Add `anubis/anubis:latest` container to `specs/cluster/manifests/frontend/deployment.yaml`
      (sidecar: listens on 8929, forwards to `localhost:8080` = the fe-gateway container port)
- [ ] Update the fe-gateway Service / Ingress to point at port 8929 (Anubis) instead of 8080
- [ ] Wire `ANUBIS_BIND=:8929` and `ANUBIS_TARGET=http://localhost:8080` via ConfigMap
- [ ] Configure `ANUBIS_DIFFICULTY` (default 5 — proof-of-work iterations; tune to challenge
      cost vs. legitimate-user friction tradeoff)
- [ ] Add bot-signature rules (`ANUBIS_BOTS_POLICY`) for known scraper UA patterns
- [ ] Gate behind a generator `optional-services.yaml` opt-in or make it default-on
      (recommendation: default-on for all fe-gateway deployments; operators disable via
      `ANUBIS_DIFFICULTY=0` / policy file to NO-OP challenges)
- [ ] Validate that `/api/auth/**` + `/actuator/health` bypass the challenge (Anubis supports
      path exemptions via its policy config — the fe-gateway's public auth paths must be exempt
      so the login flow isn't challenged before a user has any JS context)
- [ ] Add QEMU/e2e regression: `verify-client.sh` should confirm the fe-gateway reachable
      through Anubis after a clean login (a PoW-failed early abort shows as a 429 mid-test)

### Security notes

- Anubis is **not a WAF** and does not replace the gateway's JWT/route-access enforcement;
  it only adds a pre-authentication friction layer.
- For authenticated API paths (those behind Casdoor JWT) Anubis may be bypassed once the
  browser holds a valid session cookie/token — that is intentional (re-challenging every API
  call would break the SPA). The challenge only fires on unauthenticated / unknown clients.
- Public paths (registration, login callback) need exemptions to prevent the login flow
  from PoW-looping itself.

---

## Relationship to the platform

- **Gateways** — one shared `snapdragon-gateway` image; this overlay is its frontend
  instance. The be-gateway, identity (pki) gateway and games gateway are siblings off
  the same image.
- **Casdoor** — the gateway is a resource server only; it validates JWTs minted by the
  brand's Casdoor (fronted by the pki-gateway) and never exposes a login.
- **Federation** — the host shell behind this gateway is the module-federation host;
  the same domain-scoping and route-access rows that gate ordinary traffic also gate
  federated/remote surfaces, with `SUPERADMIN` the only cross-domain reach.
- **Multi-tenancy** — per-brand instances each carry their own issuer + `gateway`
  name + route-access rows; the issuer-keyed `DOMAIN_<x>` scoping + the cross-domain
  hard-deny enforce brand isolation at the gateway.

The route table and per-instance config that actually run in the cluster are rendered
by the generator's ArgoCD Application (shared `snapdragon-gateway` Helm chart with
`instance.name: snapdragon-fe-gateway` + the fe `routes`); the admin-bff CRUDs the
`gateway_route_access` rows. This repo's `application-fe.yml` and `liquibase/changelog`
are the standalone/local-dev mirror of that same identity — keep them in sync with the
generator Application, which stays the deployed source of truth.
