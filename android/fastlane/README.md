fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## Android

### android internal

```sh
[bundle exec] fastlane android internal
```

Build and upload to the internal track with the full listing

### android internal_upload

```sh
[bundle exec] fastlane android internal_upload
```

Upload the already-built AAB to the internal track

### android release

```sh
[bundle exec] fastlane android release
```

Build and upload to production

### android promote

```sh
[bundle exec] fastlane android promote
```

Promote internal to production

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
