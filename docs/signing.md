# Building, signing and notarizing

Apple is notorious for its bureaucracy so we're going to automate it.

Look at `build.sh`

Output: `dist/<AppName>-<version>.dmg`

## What you need

- A Mac with Xcode (or the command line tools) and [create-dmg](https://github.com/create-dmg/create-dmg)
- A **paid Apple Developer Program** membership. Signing and notarizing for distribution outside the App Store isn't possible without one.
- Your **own** Developer ID Application certificate and notarization credentials. If you work as a team, your account must have an **Account Holder** role (or so I'm told).
- Homebrew

## 1. Install the tools

```bash
xcode-select --install        # or install Xcode from the App Store
brew install create-dmg
```

## 2. Configure the script

Look at the `CONFIG` block at the top of `build-dmg.sh` for your project:

| Variable                | Meaning                                         |
| ----------------------- | ----------------------------------------------- |
| `APP_NAME`              | Name of the built `.app`, without the extension |
| `SCHEME`                | Xcode scheme to build                           |
| `PROJECT` / `WORKSPACE` | Your `.xcodeproj` or `.xcworkspace`             |
| `NOTARY_PROFILE`        | Keychain profile name from step 4               |
| `ENTITLEMENTS`          | Optional path to your `.entitlements` file      |

You're likely want to keep all variables as they are. I don't use entitlements and .xcworkspace

Useful commands for finding the right values:

```bash
xcodebuild -list
xcodebuild -project <proj> -scheme <scheme> -showBuildSettings | grep FULL_PRODUCT_NAME
```

Now we're going to do the required bureaucracy.

## 3. Create a Developer ID Application certificate

1. Verify that you have an active membership [here](https://developer.apple.com/account), **Membership details**
2. Write down Apple ID email, it will be used later as `"YOUR_APPLE_ID"` and Team ID, it will be used later as `"YOUR_TEAM_ID"`
3. Verify that you have an Account Holder role [here](https://appstoreconnect.apple.com/access/users). Alternatively, in Xcode go to **Settings → Accounts → (your team)**. For me it shows an "Admin" and I guess that's enough.
4. Then you'll need a **Developer ID Application** certificate. You can click **Manage Certificates…** → **+** → **Developer ID Application**. I don't know where to go next, because it spits an error that "This operation can only be performed by the Account Holder". Looks like it was not enough after all. That makes no sense because I have that role, so if that's the case for you, we'll do it manually. Don't worry it's faster than you think.

Just in case, run this to show what certs for codesigning you have:

```bash
security find-identity -v -p codesigning
```

If you have a `Developer ID Application: Your Name (YOUR_TEAM_ID)` then congratulations, you have the right certificate, you can skip to the next part. If not, follow the next steps:

4. Open **Keychain Access.app**
5. In Keychain Access menu (top left corner of the screen) go to **Certificate Assistant → Request a Certificate From a Certificate Authority…**
6. Set _User Email Address_ to `"YOUR_APPLE_ID"`
7. Set _Common Name_ to your name on Apple account
8. Set "Request is" to _Saved to disk_.
9. Click **Continue**. The certificate (`.certSigningRequest`) will be saved to disk, keep that file close
10. go to [Certificates, IDs & Profiles](https://developer.apple.com/account/resources/certificates/list)
11. Click **+ → Developer ID Application → Continue** (_This certificate is used to code sign your app for distribution outside of the Mac App Store Connect._ — that's what we're going to do), upload the file from previous step, and send it. You'll get the `.cer` file back.
12. Double-click the `.cer` to install it.

Run this again to check that you have the codesigning cert starting with "Developer ID Application":

```bash
security find-identity -v -p codesigning
```

## 4. Store notarization credentials

1. go to [account.apple.com](https://account.apple.com/account/manage) → **Sign-In and Security → App-Specific Passwords**.
2. Create a new app-specific password, write it down too (`"APP_SPECIFIC_PASSWORD"`). It may scold you for logging in via passkey if you did that and ask to re-login via password.
3. Run this to save credentials to be used for signing (the `"notary-profile"` is the same string as in config)

```bash
xcrun notarytool store-credentials "notary-profile" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

Validate

```bash
xcrun notarytool history --keychain-profile "notary-profile" | head -5
```

whew, now we can finally build the thing.

## 5. Run the build

From the folder containing your `.xcodeproj`:

```bash
chmod +x build.sh
./build.sh
```

## Verifying the result

```bash
spctl --assess --type open --context context:primary-signature --verbose=2 dist/*.dmg
xcrun stapler validate dist/*.dmg
```

Expected: `accepted` with `source=Notarized Developer ID`, and `The validate action worked!`.
