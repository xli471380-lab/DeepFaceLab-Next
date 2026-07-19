# Security and Responsible Use

## Supported development branches

Security and privacy fixes should target `develop` through a scoped pull request. The historical `master` branch remains the frozen upstream baseline until a reviewed release is prepared.

## Reporting a vulnerability

Do not publish exploit details, credentials, private paths, identity datasets, face images, trained models, or other sensitive artifacts in a public issue.

When reporting a problem, provide the minimum information needed to reproduce it:

- Affected commit and branch.
- Operating system and runtime versions.
- Redacted logs and stack traces.
- Reproduction steps using non-sensitive test data.
- Expected and actual behavior.
- Potential impact.

Until a private reporting channel is configured, open a public issue containing only a high-level description and request maintainer contact. Do not attach secrets or biometric media.

## Biometric and identity data

Face images, extracted face sets, embeddings, checkpoints, DFM files, and output videos may contain sensitive biometric or identity information.

Project rules:

- Use only media for which all relevant people have given explicit permission.
- Do not use this project to impersonate, defraud, harass, blackmail, evade identity checks, or create non-consensual intimate content.
- Do not use minors' likenesses.
- Keep private media and trained identity models outside the repository.
- Review logs and screenshots for faces, usernames, local paths, tokens, and metadata before sharing.
- Clearly disclose synthetic or altered media when it is published or streamed.
- Follow applicable platform rules and local law.

## Repository hygiene

Before every pull request:

```text
git status
git diff --cached
git ls-files
```

Confirm that the change does not include:

- Source or destination media.
- Extracted face datasets.
- Model checkpoints or exported DFM files.
- API keys, tokens, cookies, or credentials.
- Private user paths or machine identifiers.
- Large generated binaries unless explicitly reviewed.

## Dependency and binary policy

- Prefer source-verifiable dependencies and record exact versions and hashes.
- Do not silently download or execute unknown third-party binaries.
- Treat historical release bundles as untrusted until hashes and provenance are documented.
- Do not disable Windows security controls as a default installation step.
- Any installer that changes PATH, execution policy, drivers, CUDA, or system packages must explain the change and support rollback.

## Model and output claims

Do not claim that a model is safe, undetectable, authentic, production-ready, or compatible without documented evidence. Benchmarks must identify the environment, dataset characteristics, settings, and limitations.