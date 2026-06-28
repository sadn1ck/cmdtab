set dotenv-load := true

app_name := "CmdTab"
bundle_id := "com.sadn1ck.apps.cmdtab"
configuration := env_var_or_default("CONFIGURATION", "debug")
macos_deployment_target := "14.0"
swift_opt := if configuration == "release" { "-O" } else { "-Onone" }

# Code signing (self-signed, no Apple account needed). Generate once with
# `just cert`; keep the single .p12 in the gitignored file below, a GitHub
# secret (SIGNING_CERTIFICATE_P12 via `just export-cert`), and your password
# manager. Local and CI import this one file so the Accessibility grant
# survives upgrades. Only these two knobs are configurable:
cert_p12 := env_var_or_default("CERT_P12", ".secrets/cmdtab-codesign.p12")
cert_password := env_var_or_default("CERT_PASSWORD", "cmdtab")

# Internal constants.
sign_identity := "CmdTab"
signing_keychain := env_var("HOME") / "Library/Keychains/cmdtab-codesign.keychain-db"

build_dir := ".build" / configuration
app_dir := build_dir / (app_name + ".app")
contents_dir := app_dir / "Contents"
macos_dir := contents_dir / "MacOS"
resources_dir := contents_dir / "Resources"
executable := macos_dir / app_name

# List available recipes.
default:
    @just --list

# Build and sign the .app bundle.
build: cert
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{macos_dir}}" "{{resources_dir}}"
    cp Config/Info.plist "{{contents_dir}}/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier {{bundle_id}}" "{{contents_dir}}/Info.plist" >/dev/null
    xcrun swiftc \
        -parse-as-library \
        -target arm64-apple-macosx{{macos_deployment_target}} \
        {{swift_opt}} \
        -framework AppKit \
        -framework ApplicationServices \
        -framework CoreGraphics \
        -framework Security \
        -framework SwiftUI \
        -o "{{executable}}" \
        $(find Sources/{{app_name}} -name '*.swift' | sort)
    security unlock-keychain -p "{{cert_password}}" "{{signing_keychain}}"
    # Sign with whatever identity is in the dedicated keychain (by hash), so a
    # cert rename or a slightly stale secret never breaks signing by name.
    identity=$(security find-identity -p codesigning "{{signing_keychain}}" | awk '/"/{print $2; exit}')
    if [ -z "$identity" ]; then echo "==> No code-signing identity in {{signing_keychain}}" >&2; exit 1; fi
    codesign --force --sign "$identity" --keychain "{{signing_keychain}}" --entitlements "Config/{{app_name}}.entitlements" "{{app_dir}}"

# Build + sign + zip into a self-contained artifact (used by CI and releases).
dist: build
    rm -f "{{build_dir}}/{{app_name}}.zip"
    ditto -c -k --keepParent "{{app_dir}}" "{{build_dir}}/{{app_name}}.zip"
    @echo "Packaged {{build_dir}}/{{app_name}}.zip"

# Bump the version (patch|minor|major) and make the release commit. The commit
# message carries `#release`, which is what tells CI to publish a GitHub
# Release for the new version on push. Run `git push` afterwards.
release level:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{level}}" in patch|minor|major) ;; *) echo "usage: just release patch|minor|major" >&2; exit 1 ;; esac
    plist="Config/Info.plist"
    current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
    IFS=. read -r major minor patch <<< "$current"
    case "{{level}}" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
    esac
    new="$major.$minor.$patch"
    build=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$plist")
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $new" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build + 1))" "$plist"
    git commit -m "#release: v$new" -- "$plist"
    echo "==> Bumped $current -> $new. Now run: git push" >&2

# Idempotently ensure the signing identity is in the keychain. If the .p12
# exists it is imported as-is (this is what CI does after decoding the secret);
# otherwise a self-signed code-signing cert is generated into it.
cert:
    #!/usr/bin/env bash
    set -euo pipefail
    if security find-certificate -c "{{sign_identity}}" "{{signing_keychain}}" >/dev/null 2>&1; then
        echo "==> Signing identity '{{sign_identity}}' already present" >&2
        exit 0
    fi
    echo "==> Setting up signing identity '{{sign_identity}}'" >&2
    if [ ! -f "{{cert_p12}}" ]; then
        echo "    generating self-signed code-signing certificate" >&2
        mkdir -p "$(dirname "{{cert_p12}}")"
        tmp=$(mktemp -d)
        openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
            -days 3650 -nodes -subj "/CN={{sign_identity}}" \
            -addext "basicConstraints=critical,CA:false" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=critical,codeSigning"
        if openssl version | grep -q "OpenSSL 3"; then legacy="-legacy"; else legacy=""; fi
        openssl pkcs12 -export $legacy -out "{{cert_p12}}" -inkey "$tmp/key.pem" \
            -in "$tmp/cert.pem" -passout "pass:{{cert_password}}" -name "{{sign_identity}}"
        rm -rf "$tmp"
    else
        echo "    importing existing certificate {{cert_p12}}" >&2
    fi
    [ -f "{{signing_keychain}}" ] || security create-keychain -p "{{cert_password}}" "{{signing_keychain}}"
    security set-keychain-settings "{{signing_keychain}}"
    security unlock-keychain -p "{{cert_password}}" "{{signing_keychain}}"
    security import "{{cert_p12}}" -k "{{signing_keychain}}" -P "{{cert_password}}" -T /usr/bin/codesign -A >&2
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "{{cert_password}}" "{{signing_keychain}}" >/dev/null
    echo "==> Identity ready in {{signing_keychain}}" >&2

# Print the certificate as base64 to paste into the GitHub secret
# SIGNING_CERTIFICATE_P12 (and your password manager).
export-cert: cert
    @base64 -i "{{cert_p12}}" | tr -d '\n'; echo

# Remove the signing keychain and certificate (reset).
delete-cert:
    -security delete-keychain "{{signing_keychain}}" 2>/dev/null
    -rm -f "{{cert_p12}}"
    @echo "Removed signing keychain and certificate"

# Build then launch the app.
run: build
    -pkill -x {{app_name}}
    open "{{app_dir}}"

clean:
    rm -rf .build

# Helpful during development if macOS privacy prompts get into a bad state.
reset-tcc:
    -tccutil reset Accessibility {{bundle_id}}
