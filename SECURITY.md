# Security Policy

## Scope

This repository is a thin overlay on the shared
[hugmesh-gateway](https://github.com/hugmesh/hugmesh-gateway) image. It adds only
the frontend gateway's name, its route configuration (`application-fe.yml`) and the
Liquibase changesets that seed its route table (`liquibase/changelog/`). Report
problems in those files here: a route that sends traffic somewhere it should not
go, a seeded URI that is wrong or unsafe, or a build in this repo's `Dockerfile`
that weakens the image it overlays.

Authentication, authorization, the JWT and session handling, route-access
enforcement and every other piece of gateway code live in `hugmesh-gateway`.
Report vulnerabilities in that code against the `hugmesh-gateway` repository.

## Supported versions

There are no maintenance branches. The supported version is the latest commit on
`main`. Fixes land on `main`.

## Reporting a vulnerability

Report it privately. Do not open a public issue, pull request or discussion for an
unfixed vulnerability.

Use GitHub's
[private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
on this repository: open the **Security** tab and choose **Report a
vulnerability**.

Include the affected commit, the steps to reproduce it and the impact you saw. We
will acknowledge the report, agree a fix and a disclosure date with you, and tell
you when the fix ships. Keep exploit details out of public places until then.
