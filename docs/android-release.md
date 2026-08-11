# Installing & updating BudgetBox on the Android phone

This is the permanent pipeline: code on the main Mac → build on the Android-Studio Mac →
APK onto the phone. The phone carries real data, so the rules below exist to make every
update install *over* the old app without ever touching the book.

## One-time setup (on the Android-Studio Mac)

**1. Make the signing key.** Android only accepts an update signed with the *same key* as
the installed app. Without this, a rebuilt APK is "an imposter" and the phone refuses it.

```bash
keytool -genkey -v -keystore ~/budgetbox-release.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias budgetbox
# pick a password; answer the name prompts however you like
```

**2. Point the build at it.** Create `android/key.properties` (gitignored):

```properties
storePassword=<the password>
keyPassword=<the password>
keyAlias=budgetbox
storeFile=/Users/<you>/budgetbox-release.jks
```

**3. Back the keystore up** — password manager, plus a copy somewhere off that Mac.
It matters exactly like the server token: lose it and the next update can't install;
you'd have to uninstall (book restores from the server, but the PIN and a re-pairing
are on you).

Without `key.properties` the build still works — it falls back to the machine's debug
key. Fine for a first try, **not** for the real install: the debug key dies with that
Mac.

## Every update (three commands)

```bash
git pull                      # or however the code arrives
flutter pub get
flutter build apk --release --build-number=$(date +%s)
```

`--build-number=$(date +%s)` stamps each build with the current time, so every APK is
"newer" than the last — Android never refuses an install for a stale version number,
and there is nothing to remember to bump.

APK lands at `build/app/outputs/flutter-apk/app-release.apk`.

**Install** (phone on USB, debugging on):

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

or send the file to the phone and tap it.

## What survives an update

Everything: the book (SQLite in app storage), the PIN, the server address and token.
An in-place update never touches app data. The only way to lose local state is
uninstalling — and then the setup ritual's **"I already have a book"** door pulls it
all back from the server with the address + token.

## Why the repo is already set up for this

- `AndroidManifest.xml` carries `INTERNET` (release builds don't inherit it from debug —
  without it, sync silently fails only in release) and `USE_BIOMETRIC`.
- `MainActivity` extends `FlutterFragmentActivity` — `local_auth`'s biometric prompt
  refuses a plain `FlutterActivity`.
- `minSdk = 23`, which `local_auth` requires.
- `build.gradle.kts` reads `key.properties` when present, debug-signs otherwise.
