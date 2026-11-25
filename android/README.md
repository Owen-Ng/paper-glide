# Paper Glide for Android

Kotlin port of the iOS game. `android/core` is the rules (the same fixed step as `PaperGlideCore`). `android/app` is the Compose shell, the Canvas game, and the share card.

- minSdk 26, targetSdk 36, compileSdk 36
- Portrait, edge-to-edge, predictive back
- Anonymous Supabase auth. The anon key is read from `android/secrets.properties` (gitignored; see `secrets.properties.example`). A `service_role` value is treated as unconfigured. The session lives in keystore-backed encrypted prefs, which Auto Backup and device transfer exclude, so a reinstall is a new account.
- Account deletion URL (the form page comes later): `https://paperglide.app/delete`
- `platform=android` is sent on `submit_run` and on analytics events. The SQL is `supabase/migrations/20261125193000_android_platform_and_delete.sql`. Do not apply it to the hosted project from here.

```sh
cd android
cp secrets.properties.example secrets.properties   # optional; placeholder stays offline
echo "sdk.dir=$ANDROID_HOME" > local.properties
./gradlew :core:test :app:assembleDebug
```

UI tests need an emulator. The workflow runs a 720×1280 (360×640 dp) profile on API 26 and 29, and a Pixel 7 Pro profile on API 35 and 36.
