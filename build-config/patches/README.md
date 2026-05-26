# Third-Party Ballerina Package Patches

This directory contains vendored patches for upstream Ballerina packages that have
not yet shipped required fixes in a published version on Ballerina Central.

The `BallerinaPlugin` Gradle task `applyThirdPartyPatches` runs before every `balBuild`
and overlays each patch onto the corresponding bala in `~/.ballerina/`.

## Structure

```
patches/
└── <org>-<package>/
    └── <version>/          ← mirrors the bala's java21/ subdirectory
        ├── modules/
        │   └── <package>/
        │       └── types.bal
        └── platform/
            └── java21/
                └── <package>-native-<version>.jar
```

## Current Patches

### `xlibb-solace/0.4.1`

**Why**: The published `xlibb/solace 0.4.1` package does not expose a `dmqEligible` field
on the `Message` record and does not call `jcsmpMessage.setDMQEligible()` in the native layer.
Without this, messages published to Solace cannot be flagged as DMQ-eligible, so the Solace
broker will not route them to the Dead Message Queue after max-redelivery is exceeded.

**Files patched**:
- `modules/solace/types.bal` — adds `boolean dmqEligible?` to the `Message` record
- `platform/java21/solace-native-0.4.1.jar` — patches `MessageConverter` to call
  `jcsmpMessage.setDMQEligible(dmqEligible)` when `dmqEligible=true` is set

**Remove when**: `xlibb/solace 0.4.2+` (or whichever version includes the upstream fix)
is published to Ballerina Central and the dependency version in `messagestore/Ballerina.toml`
is updated accordingly.

**Upstream PR**: TODO — open a PR at https://github.com/xlibb/module-solace
