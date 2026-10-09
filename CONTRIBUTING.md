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
roc test package/main.roc
```

Check and manually run every example affected by the change.

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

3. Pull the latest `main`.

4. Publish the release with:

   ```sh
   ./release.sh <tag>
   ```

   The script runs the test suite, checks every runnable example, creates the
   content-addressed `.tar.zst` bundle under `dist/<tag>/`, and asks for
   confirmation before creating the GitHub release and tag with the committed
   release notes.

5. After publishing, replace the local `package/main.roc` dependency in every
   runnable example with the released bundle URL:

   ```roc
   tc: "https://github.com/obust/terrocotta/releases/download/<tag>/<bundle>.tar.zst",
   ```

6. Run `roc check` on every example again, then submit the updated package URLs
   as a separate post-release commit and pull request.

7. Verify the release URL from a clean consumer project.
