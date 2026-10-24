# Product images

Product photos of JBL headphones that the menu bar app shows for the connected model, in the colour the headphones report.

## Ownership and disclaimer
**These images are not part of this project and are not covered by its MIT License.**

- All images in this folder are the property of **Harman International Industries, Incorporated** (a subsidiary of Samsung Electronics) or its licensors. All rights stay with them.
- JBL, Harman, Tune, Live, Endurance and the product names are trademarks of Harman International Industries, Incorporated or its affiliates.
- They were taken unchanged from the publicly distributed JBL Headphones Android app, which ships them as plain image files. They are not edited, and no new image was made from them.
- They are included only to show which device is connected to the app (identification). They do not claim or suggest any endorsement.
- JBL Protocol4 is an **unofficial** project. It is not made, affiliated with, authorized, sponsored or endorsed by JBL, Harman International Industries or Samsung Electronics.
- Do not reuse these images in other projects on the grounds that they are in this repository. This repository gives no rights to them.

**Rights holders:** if you want any of these images removed, open an issue at https://github.com/NeoHBz/JBLProtocol4/issues or contact the repository owner. They will be removed promptly, and the app will show a generic headphones symbol instead.

## Contents
- 145 colour photos and 34 model defaults, about 9 MB, for every Protocol4 model the JBL app has a photo for.
- `<pid>_<Colour>.webp`: one photo per colour. `<pid>` is the ProductID in lower-case hex, `<Colour>` the JBL app's colour key. Example: `215f_Blue.webp` is the Tune 780NC in blue.
- `<pid>.webp`: the model's default, used when the colour is unknown or has no photo (the Black photo when there is one).
- Models without a photo (Live Beam 4, Live Flex 4) show the headphones symbol.

How the app picks an image: `Sources/JBLProtocol4/ProductImage.swift`. How the JBL app stores them: `notes/protocol.md` section 12. Model names for each ProductID: `Sources/JBLKit/Products.swift` and `notes/protocol.md` section 11.

## Updating
`scripts/bundle.sh` copies the images in this folder into every build, including releases. This README is not copied.

To refresh them from a newer JBL app, decompile it with apktool and run:

    scripts/product-images.sh

It reads `decompiled/apktool` at the main checkout's root, or the folder in `JBL_APK_DIR`, and replaces the images here (this README stays). Check the result with `git status` before you commit.
