# MECBook

KOReader plugin to read books borrowed on [MEC Livros](https://meclivros.mec.gov.br) on a jailbroken Kindle, treating each loan as a loan: the book is removed from the device when the loan ends.

## Disclaimer

- Not affiliated with, endorsed by or connected to the Brazilian Ministry of Education (MEC).
- Not a piracy tool and not meant for redistribution. It only accesses active loans of your own account.
- Each user uses their own account at their own risk. MEC may block access at any time.

## Install and update

Requires a Kindle running KOReader.

- **With Storefront** (recommended): install the plugin from the Storefront plugin store. Updates appear there when a new GitHub release is published, and need Wi-Fi.
- **By hand**: download `mecbook.koplugin-v<version>.zip` from the latest release and unzip it into `koreader/plugins/` (it contains the `mecbook.koplugin/` folder). Restart KOReader.

Updating replaces only the plugin folder. Settings and keys live in `koreader/settings/` and are kept.

## Access keys

The platform has no username/password login. Copy `mecbook_tokens.lua.sample` to `koreader/settings/mecbook_tokens.lua` and fill in the `auth_token` and `refresh_token` cookies from a logged-in browser session. The plugin imports them when it opens and blanks the file. The refresh key lasts about 30 days and renews on use.

## Releasing

1. Bump `VERSION` in `mecbook.koplugin/main.lua`.
2. `git tag vX.Y.Z && git push --tags`. A tag containing `-` (for example `v0.2.0-rc1`) is published as a pre-release.
3. The Release workflow runs luacheck and busted, builds the zip with `scripts/package.py` and attaches it to a GitHub release.

## Development

```
luacheck .
busted
```

## License

MIT. See `LICENSE`.
