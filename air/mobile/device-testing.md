# Physical iPhone review

The 2026-10-11 development package was installed on the connected iPhone 14 Pro
Max (iOS 27.0). The original Ekoloko landing screen was visually verified in
Device Hub. Login and authenticated gameplay remain user checks.

Bundle ID: `org.ekoloko.mobilephone`. Profile: `Ekoloko iPhone Development
20261011`, expires 2027-10-11. This is `ipa-test-interpreter`, a real-device
development build, not an optimized App Store build.

Signing materials live outside the repository under the current user's
`Library/Application Support/EkolokoDeviceSigning/26945TW3ZJ` directory.
Never copy its private key, password file, or PKCS12 file into the app or Git.

Build with `run_phone.py`, then use `package_phone_device.py --help` for the
explicit certificate/profile/password-file/device arguments. Packaging checks
the profile, device membership, expiration, content hashes and bundle signature.
Install the resulting `air/build/mobile-phone/apple-device/Payload/EkolokoPhoneReview.app`
with `xcrun devicectl device install app --device <connected-device> <app>`.
Launch `org.ekoloko.mobilephone` with `devicectl device process launch`.

The initial launch was correctly stopped by the pinned version-map check:
the public text counter changed from 3816 to 3865. All other XML values were
unchanged. `run_phone.py --version-map <current.xml> --baseline-version-map
<original.xml>` now supports explicitly reviewed text-only map updates at build
time. The baseline must match the existing content receipt; executable/resource
changes or text-counter downgrades fail. Runtime integrity checks remain intact.
The current XML used for this build is in `air/build/mobile-phone/current-public-files-version.xml`.
The baseline is the existing connected test's `Local Store/public-source/conf/files_version.xml`.

Evidence: `air/build/mobile-phone/device-receipt.json`, `device-install.json`,
`package-device.log`, and `device-startup-verified.png`. Automatic in-game
screenshots are disabled. No App Store or TestFlight submission was performed.
