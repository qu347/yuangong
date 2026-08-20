# Security Policy

## Supported versions

Security fixes target the current `main` branch. This repository does not yet publish supported production release versions.

## Reporting a vulnerability

Do not open a public issue containing exploit details, credentials, employee information, invitation links, reset links, or audit exports.

Report vulnerabilities privately through [GitHub Security Advisories](https://github.com/qu347/yuangong/security/advisories/new). Include the affected component, reproducible impact, and a minimal safe proof of concept. Remove passwords, tokens, keys, certificates, real employee data, and email bodies before submitting.

The maintainers will acknowledge the report through the private advisory. No public security contact email has been approved for this project.

## Scope

In scope are the Django API, Flutter Windows/Android clients, authentication and authorization, audit export/archive integrity, production configuration contracts, and build/release scripts.

Do not test against production systems, real employee accounts, external mail providers, or infrastructure that you do not own or have explicit permission to assess.
