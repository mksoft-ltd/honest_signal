fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios metadata_only

```sh
[bundle exec] fastlane ios metadata_only
```

Upload metadata + screenshots only (no binary, no submission)

### ios upload_build

```sh
[bundle exec] fastlane ios upload_build
```

Upload the already-built IPA to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Build and submit to the App Store

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
