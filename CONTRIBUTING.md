# Contributing to Terrocotta

Thanks for helping improve Terrocotta.

## Repository structure

- `package/` — the Terrocotta library
- `package/widgets/` — proof-of-concept widgets
- `examples/` — runnable applications and the interactive tutorial
- `bench/` — traced performance workloads, queries, and allocation baselines
- `docs/` — architecture notes and project documentation

## Architecture

Read the [architecture overview](docs/architecture.md) before changing public
APIs or behavior that crosses layout, painting, rendering, or application-state
boundaries.

Open an issue before proposing a broad public API change or a substantial new
subsystem so its design can be discussed first.

## Validation

Before opening a pull request, run:

```sh
scripts/check.sh
scripts/test.sh
scripts/bundle.sh --output-dir dist
```

The scripts validate formatting, run the package and example tests, and check
every example listed in `scripts/utils.sh` against the working package.
Manually run examples affected by the change.

## Tests

Add regression coverage for behavioral fixes when possible.

Use top-level `expect` tests with a short `##` comment describing the behavior
under test.

## Visual changes

For changes that affect visible output:

- Run the affected examples.
- Include screenshots for visual changes.
- Update README or documentation captures when necessary.

## Documentation

Update relevant documentation when changing public APIs, architecture, or
example usage.

## Assets

When adding third-party images, fonts, shaders, or other assets, document their
source and license.

## Publishing releases

1. Create a release branch containing `docs/release/<tag>.md` (based on `docs/release/TEMPLATE.md`).

2. Open and merge the release branch into `main`.

3. Run the Release workflow on `main`: **Actions → Release**, choose **Run workflow**.

The workflow checks and tests the sources, validates the API version bump,
builds one content-addressed archive, and publishes it with the committed
release notes.

NB: `scripts/release.sh <tag>` remains available as a manual fallback. It does
not perform the cross-platform or API-version checks provided by CI.
