set dotenv-load
set default-list

app_name := "CmdTab"
bundle_id := "com.sadn1ck.apps.cmdtab"
configuration := env_var_or_default("CONFIGURATION", "debug")
macos_deployment_target := "26.0"
swift_opt := if configuration == "release" { "-O" } else { "-Onone" }

# Code signing configuration.
cert_p12 := env_var_or_default("CERT_P12", ".secrets/cmdtab-codesign.p12")
cert_password := env_var_or_default("CERT_PASSWORD", "cmdtab")
sign_identity := "CmdTab"
signing_keychain := env_var("HOME") / "Library/Keychains/cmdtab-codesign.keychain-db"

build_dir := ".build" / configuration
app_dir := build_dir / (app_name + ".app")
contents_dir := app_dir / "Contents"
macos_dir := contents_dir / "MacOS"
resources_dir := contents_dir / "Resources"
executable := macos_dir / app_name

# Build then launch the app.
[group('dev')]
run: build
    -pkill -x {{ app_name }}
    open "{{ app_dir }}"

# Remove local build artifacts.
[group('dev')]
clean:
    rm -rf .build

# Reset macOS Accessibility permission state for CmdTab.
[group('dev')]
reset-tcc:
    -tccutil reset Accessibility {{ bundle_id }}

# Build and sign the .app bundle.
[group('prod')]
build: cert
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p "{{ macos_dir }}" "{{ resources_dir }}"
    cp Config/Info.plist "{{ contents_dir }}/Info.plist"
    cp Resources/CmdTab.icns "{{ resources_dir }}/CmdTab.icns"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier {{ bundle_id }}" "{{ contents_dir }}/Info.plist" >/dev/null
    xcrun swiftc \
        -parse-as-library \
        -target arm64-apple-macosx{{ macos_deployment_target }} \
        {{ swift_opt }} \
        -framework AppKit \
        -framework ApplicationServices \
        -framework CoreGraphics \
        -framework Security \
        -framework SwiftUI \
        -o "{{ executable }}" \
        $(find Sources/{{ app_name }} -name '*.swift' | sort)
    security unlock-keychain -p "{{ cert_password }}" "{{ signing_keychain }}"
    identity=$(security find-identity -p codesigning "{{ signing_keychain }}" | awk '/"/{print $2; exit}')
    if [ -z "$identity" ]; then echo "==> No code-signing identity in {{ signing_keychain }}" >&2; exit 1; fi
    codesign --force --sign "$identity" --keychain "{{ signing_keychain }}" --entitlements "Config/{{ app_name }}.entitlements" "{{ app_dir }}"

# Build, sign, zip, and checksum a release artifact.
[group('prod')]
dist: build
    rm -f "{{ build_dir }}/{{ app_name }}.zip"
    ditto -c -k --keepParent "{{ app_dir }}" "{{ build_dir }}/{{ app_name }}.zip"
    (cd "{{ build_dir }}" && shasum -a 256 "{{ app_name }}.zip" > "{{ app_name }}.zip.sha256")
    @echo "Packaged {{ build_dir }}/{{ app_name }}.zip"
    @echo "Checksum: {{ build_dir }}/{{ app_name }}.zip.sha256"

# Install the latest published GitHub release into /Applications.
[group('prod')]
install:
    curl --fail --location https://raw.githubusercontent.com/sadn1ck/cmdtab/main/install.sh | bash

# Create or import the local code-signing identity.
[group('prod')]
cert:
    #!/usr/bin/env bash
    set -euo pipefail
    if security find-certificate -c "{{ sign_identity }}" "{{ signing_keychain }}" >/dev/null 2>&1; then
        echo "==> Signing identity '{{ sign_identity }}' already present" >&2
        exit 0
    fi
    echo "==> Setting up signing identity '{{ sign_identity }}'" >&2
    if [ ! -f "{{ cert_p12 }}" ]; then
        echo "    generating self-signed code-signing certificate" >&2
        mkdir -p "$(dirname "{{ cert_p12 }}")"
        tmp=$(mktemp -d)
        openssl req -x509 -newkey rsa:2048 -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
            -days 3650 -nodes -subj "/CN={{ sign_identity }}" \
            -addext "basicConstraints=critical,CA:false" \
            -addext "keyUsage=critical,digitalSignature" \
            -addext "extendedKeyUsage=critical,codeSigning"
        if openssl version | grep -q "OpenSSL 3"; then legacy="-legacy"; else legacy=""; fi
        openssl pkcs12 -export $legacy -out "{{ cert_p12 }}" -inkey "$tmp/key.pem" \
            -in "$tmp/cert.pem" -passout "pass:{{ cert_password }}" -name "{{ sign_identity }}"
        rm -rf "$tmp"
    else
        echo "    importing existing certificate {{ cert_p12 }}" >&2
    fi
    [ -f "{{ signing_keychain }}" ] || security create-keychain -p "{{ cert_password }}" "{{ signing_keychain }}"
    security set-keychain-settings "{{ signing_keychain }}"
    security unlock-keychain -p "{{ cert_password }}" "{{ signing_keychain }}"
    security import "{{ cert_p12 }}" -k "{{ signing_keychain }}" -P "{{ cert_password }}" -T /usr/bin/codesign -A >&2
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "{{ cert_password }}" "{{ signing_keychain }}" >/dev/null
    existing=$(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')
    if ! printf '%s\n' "$existing" | grep -qxF "{{ signing_keychain }}"; then
        security list-keychains -d user -s "{{ signing_keychain }}" $existing
    fi
    echo "==> Identity ready in {{ signing_keychain }}" >&2

# Print the signing certificate as base64 for the GitHub secret.
[group('prod')]
export-cert: cert
    @base64 -i "{{ cert_p12 }}" | tr -d '\n'; echo

# Remove the local signing keychain and certificate.
[group('prod')]
delete-cert:
    -security delete-keychain "{{ signing_keychain }}" 2>/dev/null
    -rm -f "{{ cert_p12 }}"
    @echo "Removed signing keychain and certificate"

# Bump the version and create the release commit used by CI.
[group('release')]
release level="patch":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ level }}" in patch|minor|major) ;; *) echo "usage: just release patch|minor|major" >&2; exit 1 ;; esac
    plist="Config/Info.plist"
    current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")
    IFS=. read -r major minor patch <<< "$current"
    case "{{ level }}" in
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
