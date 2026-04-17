# LSerial Release

This project uses GitHub Actions to build release packages when a version tag is pushed.

## Create a Release

Update `pubspec.yaml` first:

```yaml
version: 1.0.0+1
```

Then tag and push:

```powershell
git add .
git commit -m "release: v1.0.0"
git tag v1.0.0
git push
git push origin v1.0.0
```

GitHub Actions will create a GitHub Release and upload:

- `LSerial-v1.0.0-Windows-x64-portable.zip`
- `LSerial-v1.0.0-Windows-x64-Setup.exe`
- `LSerial-v1.0.0-macOS.zip`
- `LSerial-v1.0.0-macOS.dmg`
- `LSerial-v1.0.0-Linux-x64.tar.gz`
- `LSerial-v1.0.0-Web.zip`

## Manual Release

Open GitHub Actions, run the `Release` workflow manually, and enter a version such as:

```text
v1.0.0
```

## Notes

- Windows installer is built with Inno Setup.
- macOS packages are unsigned. Without Apple notarization, macOS may show a security warning.
- Linux package is a portable tarball.
- Web package contains the static files from `build/web` and can be deployed to Cloudflare Pages.
