# Contributing to Terrocotta

Thanks for helping improve Terrocotta.

## Repository structure

- `package/` — the Terrocotta library
- `package/widgets/` — proof-of-concept widgets
- `examples/` — runnable applications and the interactive tutorial
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

The scripts validate formatting, run the package tests, and check every example
listed in `scripts/utils.sh`. If an example uses a published `tc` URL,
`check.sh` replaces it with the working `package/main.roc` for that invocation
so released code cannot hide a local regression. Manually run examples affected
by the change.

## Tests

Add regression coverage for behavioral fixes when possible.

Use top-level `expect` tests with a short `##` comment describing the behavior
under test.

## Visual changes

For changes that affect visible output:

- Run the affected examples.
- Include screenshots for visual changes.
- Update README or documentation captures when necessary.

## Documentation and assets

Update relevant documentation when changing public APIs, architecture, or
example usage.

When adding third-party images, fonts, shaders, or other assets, document their
source and license.

## Publishing releases

1. Add `docs/release/<tag>.md` (based on `docs/release/TEMPLATE.md`) in a release PR.

2. Review and merge it into `main`.

3. From **Actions → Release**, choose **Run workflow** on the branch to release
   and enter the tag without a `v` prefix.

4. The workflow checks and tests the sources, validates the API version bump,
   builds one content-addressed archive, and tests those exact bytes on Linux,
   macOS, and Windows before publishing the release with the committed notes.

5. After publishing, the workflow tests the public download and opens a
   follow-up pull request updating every example's `tc` dependency to that URL.
   Review and merge the pull request.

6. `scripts/release.sh <tag>` remains available as a manual fallback. It does
   not perform the cross-platform or API-version checks provided by CI.
