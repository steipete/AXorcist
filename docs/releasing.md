# Releasing `axorc`

The Homebrew formula consumes a Developer ID-signed universal binary. Do not publish the ad-hoc artifact produced by `--adhoc`; a stable signature keeps the macOS Accessibility identity consistent across upgrades.

## Prepare

1. Update `axorcVersion` in `Sources/axorc/Models/AXORCModels.swift` and move the changelog entries into the matching release section.
2. Run `swift test`, SwiftFormat, SwiftLint, the live CLI smoke checks, and autoreview.
3. Build with the existing Developer ID Application identity:

   ```bash
   AXORC_CODESIGN_IDENTITY='Developer ID Application: ...' scripts/build-release-artifact.sh 0.1.8
   ```

4. Submit `dist/axorc-0.1.8-macos-universal.zip` to `notarytool` using the approved release credentials. Wait for acceptance. Zip archives cannot be stapled; verify the downloaded archive online with Gatekeeper after publication.

## Publish and update Homebrew

1. Upload the zip and `.sha256` file to the matching GitHub Release.
2. Download the public artifact into a clean temporary directory. Verify its checksum, universal architectures, stable signature, `spctl` assessment, `--version`, and `--help`.
3. Render the formula with the public artifact checksum:

   ```bash
   scripts/render-homebrew-formula.sh 0.1.8 <sha256> > axorc.rb
   ```

4. Add `axorc.rb` to `openclaw/homebrew-tap`, then run `brew audit --strict axorc`, `brew install --build-from-source ./axorc.rb`, `axorc --version`, `axorc --help`, and `axorc permissions` on a clean host.
5. Confirm Homebrew preserved the published executable byte-for-byte and retained its Developer ID requirement:

   ```bash
   cmp axorc "$(brew --prefix axorc)/bin/axorc"
   codesign --verify --strict "$(brew --prefix axorc)/bin/axorc"
   codesign -d -r- "$(brew --prefix axorc)/bin/axorc"
   ```

   The designated requirement must contain `anchor apple generic`; an ad-hoc requirement is a release blocker.
6. After the tap change lands, update the README with `brew install openclaw/tap/axorc` and verify a fresh public installation.

## Close out

- Confirm the GitHub Release contains the signed universal archive and checksum.
- Confirm the Homebrew formula uses the public archive URL and exact checksum.
- Open the next patch `Unreleased` section and commit it.
