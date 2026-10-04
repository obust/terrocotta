# Screwbot asset policy

Screwbot uses one mixed asset policy. It embeds only the small, stable authored
inputs relative to `examples/screwbot/main.roc`: five fragment shader sources.
Its four material textures are always loaded through one `Assets.Store` that is
opened with `IgnoreManifest`.

The store is opened from the literal, repository-relative directory
`examples/assets`, which the app requests as a read-only capability in
`configure`:

```roc
configure = |_args|
	App.default
		.with_title("Screwbot // PGA Kinematics Lab")
		.with_size({ width: 1280, height: 900 })
		.with_resizable(True)
		.with_permission(Directory(assets_dir, ReadOnly))
```

Because the directory capability is relative, Screwbot is run from the
Terrocotta repository root:

```bash
roc run examples/screwbot/main.roc
```

There is no `SCREWBOT_ASSET_ROOT`, no environment read, and no manifest
validation. `IgnoreManifest` means the store does not look for, read, or verify
a `roc-assets.manifest`, so the shared `examples/assets` tree needs no generated
contract file and adding other examples' assets cannot invalidate Screwbot.

## Why not a manifest

A manifest would pin a content digest over the *whole* shared directory, so
every unrelated asset added by any other example would break Screwbot's startup.
Screwbot only ever reads four named files, so the store is opened with
`IgnoreManifest` and the coupling is dropped.

If a future change needs integrity checking, use `RequireManifest` with a
dedicated Screwbot-only asset directory rather than reintroducing a digest over
the shared root.

## Resource lifetime and size

The embedded shader sources are decoded during `init!`; the host retains the
resulting compiled GPU shaders and the uniform handles looked up from them. The
store reads the four material files relative to its opened directory capability
and releases temporary file bytes after decode. Loaded textures, shaders,
uniforms, and the three render targets (scene pass plus the two bloom passes)
are then owned by `AppModel` for the lifetime of the app, so every draw call
after startup is allocation-free with respect to assets.

This avoids embedding a fallback copy of the materials: the executable stays
close to its former size instead of carrying their additional payload.