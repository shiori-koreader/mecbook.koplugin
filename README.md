# MECBook

A [KOReader](https://koreader.rocks) plugin to read books borrowed on [MEC Livros](https://meclivros.mec.gov.br) (Brazilian Ministry of Education) on a jailbroken Kindle, treating each loan as a loan: the book lives on the device only while the loan lasts, and your reading progress survives it.

The interface is in Brazilian Portuguese.

## Disclaimer

- Not affiliated with, endorsed by or connected to the Brazilian Ministry of Education (MEC).
- Not a piracy tool and not meant for redistribution. It only accesses active loans of your own account, and the book is deleted from the device when the loan ends.
- Each user uses their own account at their own risk. MEC may block access at any time.

## Features

- **Search** the MEC Livros catalogue from the Kindle, with a detail screen per book: title, authors, publisher, year, pages, category, whether it is a licensed or public-domain title, availability and the synopsis (with a "read full synopsis" view).
- **Borrow and read**: borrowing downloads the book and opens it. Only one book can be on loan at a time, as the platform requires.
- **Loan rules explained in the app**: licensed books are lent for 14 days; the confirmation says the loan counts towards the platform limits (4 loans per 30 days, 4 redemptions per title, renewals included).
- **Already borrowed on the website?** Picking that book in the search just downloads it, without spending another loan. If you already hold a different book, the plugin tells you which one and until when, and offers to download it.
- **Expiry warnings**: configurable under *MECBook > Avisos de vencimento* (7, 3 or 1 days before, any number from 1 to 60, or none). Each threshold warns once per loan and shows the end date.
- **The book leaves when the loan ends**: expiry is checked without network when KOReader starts, on resume, before a book opens and with a local timer while it runs. An expired book never opens. A loan returned on the website is also removed the next time the plugin syncs.
- **Progress survives**: before removal, the book's KOReader metadata (reading position, highlights, notes) is archived by book id and restored when you borrow the same book again.
- **Notice on removal**: when you come back after the loan ended, the plugin says what happened and where you stopped, and offers to borrow the book again or search another.
- **Renewal** (+14 days), offered when the platform allows it, with a confirmation about the limits it consumes.
- **Return**: once you have read at least 90% of the book, *Meu empréstimo > Devolver* reports your real reading progress to the platform and returns the book. Before 90% the platform does not allow returning, and the screen says so.
- **Deterministic EPUB**: the same book always builds a byte-identical EPUB, which keeps annotation positions and KOReader statistics attached to the book.
- **Shortcuts**: three actions can be bound to gestures or buttons in KOReader: open MECBook, my loan, search.

## Requirements

- A Kindle with KOReader (tested on a Paperwhite 10th gen and a Paperwhite Signature Edition).
- A MEC Livros account (gov.br login).
- Wi-Fi for searching, borrowing, renewing, returning and syncing. Reading and expiry checks work offline.

## Install and update

- **With Storefront** (recommended): install MECBook from the Storefront plugin store. Updates appear there when a new GitHub release is published.
- **By hand**: download `mecbook.koplugin-v<version>.zip` from the [latest release](https://github.com/shiori-koreader/mecbook.koplugin/releases/latest) and unzip it into `koreader/plugins/` (it contains the `mecbook.koplugin/` folder). Restart KOReader.

Updating replaces only the plugin folder. Settings and keys live in `koreader/settings/` and are kept.

## Access keys

The platform has no username/password login (it uses gov.br), so the plugin needs the two session cookies of your logged-in account:

1. Log in at meclivros.mec.gov.br in a browser and open the developer tools (F12) > Application (or Storage) > Cookies.
2. Copy the values of `auth_token` and `refresh_token`.
3. Create `koreader/settings/mecbook_tokens.lua` on the Kindle (there is a `mecbook_tokens.lua.sample` in the repository):

   ```lua
   return { auth_token = "PASTE_HERE", refresh_token = "PASTE_HERE" }
   ```

4. With Wi-Fi on, open *MECBook*. The plugin imports the keys into its own settings file and blanks `mecbook_tokens.lua`.

The refresh key lasts about 30 days and renews every time it is used. If you stay longer than that without opening the plugin, repeat the steps above. Never share these keys: they give access to your account.

## Using it

Open *MECBook* from the tools menu (or from a bound gesture). The first time, it shows the disclaimer; *Sobre* shows it again later.

| Menu | What it does |
| --- | --- |
| Meu empréstimo | Shows the current loan, its end date, and the actions available: read, renew (when allowed), return (after 90%). With no local loan, it looks for one on your account and offers to download it. |
| Buscar livros | Search by title, author or subject. Tap a result for the book screen. |
| Avisos de vencimento | Choose when to be warned before a loan ends. |
| Chaves de acesso | Imports keys from `mecbook_tokens.lua`, or tells you they are already set. |
| Sobre | Shows the disclaimer again. |

## Loan rules (platform)

- Licensed books: one book at a time, 14 days, returned automatically at the end of the term, extendable by 14 days.
- Each title can be redeemed up to 4 times (loans and renewals together), and an account can make up to 4 loans per 30 days, renewals included.
- Public-domain books have no term and no limit on the platform.

## Request budget and safety

- No background polling: the plugin checks your loans only when it opens, or when the device wakes with Wi-Fi already on, and at most once per hour.
- Each book is downloaded once per loan, resources one at a time, with backoff on server errors.
- If the platform answers HTTP 403 (access blocked), the plugin stops, explains it and does not retry until it is opened again. It never works around a block.
- Keys are stored only in the plugin settings, never logged, and the import file is blanked after use.
- The EPUB is kept in a hidden folder inside the KOReader data directory, never in your library, and there is no export.

## Known limitations

- Changing the Kindle clock defeats the offline expiry check.
- Public-domain books go through the same loan flow as licensed ones. They have not been verified end to end.
- Renewal, the 90% return and the platform's 30-day loan limit message are implemented from the platform's behaviour but have not been exercised end to end on a device.
- The plugin shows your reading position as a percentage, not a chapter name.
- There is no waitlist support: books with no copies available are shown as such.

## Development

```
luacheck .
busted
```

`scripts/deploy.sh` copies the plugin to a Kindle mounted as a drive. Kindles that connect over MTP need a manual copy to `koreader/plugins/`.

Business logic lives in pure Lua modules with injected clock, filesystem and transport (`api/`, `loans/`, `epub/`, `storage/`, `books/`), and `main.lua` is the KOReader shell.

## Releasing

1. Bump `VERSION` in `mecbook.koplugin/main.lua`.
2. `git tag vX.Y.Z && git push --tags`. A tag containing `-` (for example `v1.1.0-rc1`) is published as a pre-release.
3. The Release workflow runs luacheck and busted, builds the zip with `scripts/package.py` and attaches it to a GitHub release.

## License

MIT. See `LICENSE`. Parts of the EPUB builder are adapted from [luizcorreia/meclivros.koplugin](https://github.com/luizcorreia/meclivros.koplugin) (MIT, Copyright (c) 2026 Luiz Correia).
