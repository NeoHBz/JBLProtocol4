# JBL Protocol4

Menu bar app for the JBL Tune 780NC (layout "A1"). Swift package, built with `make`, no Xcode project.

    cd mac/JBLProtocol4
    make cert        # once: creates a self-signed signing certificate in your keychain (no Apple account)
    make             # build Debug, sign, relaunch
    make test        # replays captured frames byte for byte
    make install     # signed Release build into /Applications
    make help        # every target; chain them: make build:test:zip

First launch: macOS asks whether JBL Protocol4 may use Bluetooth. Allow it. The headphones must already be bonded to this Mac.
Remove: delete `build/`, the app in /Applications, and its entry in System Settings > Privacy & Security > Bluetooth.

## Keeping your details out of the repo
Nothing personal is committed. Bundle id, signing name and version come from the environment, with generic defaults:
`JBL_BUNDLE_ID`, `JBL_SIGN_IDENTITY`, `JBL_VERSION`. Locally set them in `local.mk` (git-ignored, copy `local.mk.example`)
or leave them alone. The certificate lives in your keychain, never in a file in the repo (`*.p12` and `*.pem` are git-ignored).

## Product photos
The panel shows the connected model's photo in the colour the headphones report (ProductID and ColorID, read on connect).
The photos are JBL's, so they are not in the repo: every build copies them out of your own decompiled JBL app
(`scripts/product-images.sh`, about 9 MB, every Protocol4 model and colour). It looks in `decompiled/apktool` at the main
checkout's root, or in `JBL_APK_DIR`. Without that folder (CI, a fresh clone) the build still works and the panel shows a
headphones symbol. Live Beam 4 and Live Flex 4 have no photo in the app and always show the symbol.

## GitHub Actions
`.github/workflows/build.yml` runs the tests and builds a zip on every push and pull request. It works with no setup and signs
ad-hoc. To sign with your certificate, run `make cert-export` once and paste the three `gh` commands it prints. They store the
certificate as the secrets `JBL_CERT_P12_BASE64` and `JBL_CERT_PASSWORD` and the name as the variable `JBL_SIGN_IDENTITY`.
Pull requests from forks never see secrets, so they build ad-hoc.

Only verified commands are built (`Sources/JBLKit/Protocol.swift`, `writableTags`). Left out on purpose: EQ, Smart Audio & Video, LE Audio, Auracast, button mapping.
