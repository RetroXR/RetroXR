# `.github/ci/` — The fallback signing key

`retroxr-fallback.keystore` is a **fixed, deliberately public signing key** used for development builds.

When the official `ANDROID_KEYSTORE_*` repository secrets are not available, CI uses this keystore to sign the Quest APK. Contributors can also use the same keystore for local exports.

## Why the key is fixed

The fallback keystore must remain the same between builds.

Previously, CI generated a new keystore with `keytool` whenever the official signing secrets were unavailable. While those APKs were correctly signed, each build had a different signing identity. Android therefore could not install a new build as an update to an existing build signed with the previous key.

Using one fixed key means that fallback builds can be installed over previous fallback builds without requiring the user to uninstall the application first.

This is particularly useful for contributors and forks that do not have access to the official release signing key.

## What it is not

This is **not the production signing key**.

Official releases are still signed with the private key stored in the `ANDROID_KEYSTORE_*` repository secrets. The fallback keystore is only used when those secrets are unavailable.

Because the fallback key is public:

* anyone can use it to create a build with the same signing identity;
* it must never be used for production releases;
* an APK signed with the fallback key cannot update an APK signed with the official release key;
* an official APK cannot be replaced by a fallback-signed APK.

Fallback builds should therefore be considered **development/unofficial builds**.

Publishing the fallback keystore is intentional: it does not provide access to the official release key or any production credentials.

## Credentials

|                     |                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| File                | `.github/ci/retroxr-fallback.keystore` (PKCS#12)                                                  |
| Alias / user        | `retroxr-ci`                                                                                      |
| Store password      | `retroxr-ci`                                                                                      |
| Key password        | `retroxr-ci`                                                                                      |
| Key                 | RSA 2048, self-signed                                                                             |
| Valid until         | 2056-09-17                                                                                        |
| Certificate SHA-256 | `AC:36:EC:34:62:41:D2:1F:6B:1E:9D:95:C9:F5:B1:E0:0F:B5:0D:2A:F7:60:F0:10:C8:49:E9:BB:17:77:BE:BA` |

The credentials are documented here because they are not intended to be secret. Anyone who has access to the keystore can obtain them anyway.

The certificate fingerprint is documented so that accidental key replacement can be detected. If the fingerprint changes, fallback builds will no longer be compatible with existing fallback installations and users will need to reinstall the application.

## Signing a local export with the fallback key

Godot can read the keystore configuration directly from the environment, so nothing needs to be written to `RetroXR/.godot/export_credentials.cfg`:

```bash
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$PWD/.github/ci/retroxr-fallback.keystore"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER=retroxr-ci
export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=retroxr-ci

"$GODOT" --headless --path RetroXR --export-release "Quest" /tmp/RetroXR.apk
```

## Regenerating the key

The fallback key should only be regenerated if it is compromised or if compatibility with the target JDK requires it.

If it is regenerated, the new certificate fingerprint must also be updated in this document.

A replacement key can be generated with:

```bash
keytool -genkeypair \
  -keystore .github/ci/retroxr-fallback.keystore \
  -storetype PKCS12 \
  -storepass retroxr-ci \
  -keypass retroxr-ci \
  -alias retroxr-ci \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10950 \
  -dname "CN=RetroXR Fallback, OU=CI, O=RetroXR, C=IT"
```

`-validity 10950` provides approximately 30 years of validity. This is intentional: the previous 30-day validity period could cause the signing certificate to expire and make existing development installations problematic.

After regenerating the key, verify the certificate fingerprint and update the value documented above.

The current keystore was generated with OpenSSL rather than `keytool`, but uses a PKCS#12 format compatible with modern JDKs, including the Temurin 17 runtime used by the Quest CI job.
