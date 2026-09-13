# ios-release-kit

Diagnose what is blocking your App Store submission via the App Store Connect API, then fix it from the command line. Built from a real launch in Sept 2026. Korean docs: [README.md](README.md).

## 30-second summary
**What**: diagnose why your submission is stuck (`fastlane doctor`), fix it with one command. **Who**: you shipped the app with Claude Code or Cursor and got stuck at submission.

**Why** (a real Sept 2026 launch): missing IAP review screenshot blocked review; empty age-rating declaration blocked Submit; build never attached to the version so the draft lacked the app version; deliver crashed on a non-UTF-8 locale; review phone wasn't E.164; app name was already taken; every build asked the export-compliance question (no `ITSAppUsesNonExemptEncryption`); and after submitting, no way to tell whether the app was actually in Apple’s queue or just sitting in a draft; and `Product.products(for:)` returning an empty array with no way to tell whether the productId even exists in ASC.

## Install
```bash
brew install fastlane   # also needs Ruby 3+; macOS system Ruby 2.6 can't run this
cp -r ios-release-kit/fastlane <your-app>/fastlane   # merge lib/ + lanes if you already have fastlane
cp fastlane/.env.template fastlane/.env   # then fill it in
# ASC web -> Users and Access -> Integrations -> Generate Key (App Manager) -> .p8 to fastlane/keys/
```

## Diagnose
```bash
LC_ALL=en_US.UTF-8 fastlane doctor
```

## Fix
| Item | Command | What it does |
|---|---|---|
| Attach build | `fastlane attach_build build:<number>` | attach latest VALID build to the version being edited |
| Age rating | `fastlane age_rating override:'key=value,key=value'` | fill declaration with NONE/false, override specific keys |
| IAP screenshot | `fastlane iap_screenshot iap_id:<id> path:<png>` | upload review screenshot (or `product_id:<productId>`) |
| Metadata | `fastlane release_metadata` | upload `fastlane/metadata/<locale>/` to ASC (no submit) |
| Screenshots | `fastlane upload_screenshots` | upload `fastlane/screenshots/<locale>/<device>/*.png` to ASC |

Prefix any write lane with `DRY_RUN=1` to print the request instead of sending it.

## Ship
```bash
fastlane verify_auth        # check auth
fastlane beta                # build + TestFlight upload
cp -r fastlane/metadata.example fastlane/metadata   # fill it in, then:
fastlane release_metadata    # upload metadata
# submit manually on the ASC web, or fastlane release from v1.1+
```

## Screenshots
```bash
scripts/screenshots.sh booted fastlane/screenshots/ko/iPhone 01-home
```
Clears the simulator status bar, captures, resizes to 1320x2868 (6.9").

## Using it with Claude Code
`claude/` has a `CLAUDE.md.template`, a pre-submission review skill (`skills/app-store-review/`), and a daily-status scheduled prompt (`scheduled/review-daily.md`). Copy what you need.

## Pitfalls
Full table: [`docs/review-checklist.md`](docs/review-checklist.md). All from one real launch, nothing speculative: missing IAP screenshot, empty age rating, build not attached to the version, non-UTF-8 locale, non-E.164 phone, app name taken, missing encryption key.

## Limits
Paid-apps agreement status isn't readable via the API. Adding a version to an existing submission draft returned HTTP 500 during the real launch — `doctor` only warns and points to the web. Verified on one real launch so far, not across many apps.

## License
MIT
