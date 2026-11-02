# MECBook (mecbook.koplugin)

KOReader plugin to read books borrowed on the MEC Livros platform (https://meclivros.mec.gov.br, Brazilian Ministry of Education, gov.br login) on a jailbroken Kindle, treating each loan as a loan: the book disappears when the loan ends.

Repository: `shiori-koreader/mecbook.koplugin` (public). License: MIT.

## Working agreements

- Talk to the maintainer (Thiago) in Brazilian Portuguese. Everything written into the repo (code, comments, commits, README, docs) is in English, except user-facing UI strings, which are pt-BR.
- Comments only explain *why*. Never restate what the code does.
- Thiago is a QA engineer: business logic must be testable without KOReader and without the network. Keep KOReader UI and I/O at the edges.
- Ask before changing any decision listed under "Fixed decisions".

## Target environment

- Device: Kindle Paperwhite 10th gen (PW4), firmware 5.18.1.1.1, 1448×1072, 300 PPI, grayscale. KOReader installed via KPM. Check the KOReader version with Thiago (Help → About) before relying on newer APIs.
- KOReader runs LuaJIT (Lua 5.1 semantics).
- Primary user is Thiago's wife: UI must be simple and friendly. She uses the Kindle without a cover, so it does not sleep when "closed".
- Dev machine: Windows with Git Bash. Over USB the Kindle mounts as `D:` (`/d/`); plugins go to `/d/koreader/plugins/`.

## Prior art to reuse

`luizcorreia/meclivros.koplugin` (MIT, Copyright (c) 2026 Luiz Correia). Clone it for reference. Reusing its code is allowed; keep its copyright notice in our LICENSE alongside ours.

What it already figured out:
- Auth: JWT sent as `Authorization: Bearer <token>` to the Next.js proxy under `/api/backend/*`. Refresh via `POST /api/auth/refresh` with cookie `refresh_token=<value>` (valid ~30 days, renewed on use). New token may come in the JSON body or in `Set-Cookie: auth_token=...`; the refresh token may rotate.
- Tokens come from the browser cookies `auth_token` and `refresh_token` (DevTools). There is no username/password login (gov.br is OAuth/OIDC).
- Endpoints: `GET auth/me`, `GET books/search?query=&page=&limit=`, `GET books/:id`, `GET books/:id/manifest`, `GET rentals?status=active`, `POST rentals/checkout {bookId}`, `POST rentals/:id/extend`, `POST rentals/:id/return`.
- Content: no DRM. The web reader uses a Readium/WebPub manifest; `selfHref` contains `/webpub/<base64>/manifest.json`, and resources are served authenticated at `/epub-proxy/webpub/<base64>/<href>`. `epubbuilder.lua` downloads `readingOrder` + `resources` and synthesizes `container.xml`, `content.opf` (OPF 3), `nav.xhtml` and `toc.ncx`, then zips with `ffi/archiver`.
- Rental fields it uses: `id`, `book_id`, `book_title`, `days_remaining`, `can_extend`. The exact due-date field is unknown: confirm on the first real call and record a redacted fixture.

What we do differently: books are deleted when the loan ends, strict request budget, honest failure on blocks, disclaimers, progress preservation, testable architecture. Drop its public-domain search: it fires one detail request per search result.

## Fixed decisions

1. **User-Agent**: `Mozilla/5.0 (X11; Linux x86_64) mecbook-koreader/<version>`. Same shape as the original (passes the generic WAF filter) while naming the plugin. No contact URL.
2. **Blocks**: an HTTP 403 from the WAF stops the session: show a clear message ("o MEC Livros não está aceitando acesso por este plugin; use o site ou o app oficial") and do not retry until the plugin is opened again. Never work around a targeted block.
3. **Request budget**: no background polling. Check rental status only when the plugin opens or the device resumes with Wi-Fi already on, and at most once per hour (cached). Download each book once per loan, resources sequentially. Exponential backoff on 5xx/network errors. One refresh attempt on 401.
4. **Loans are loans (hardcoded, no setting to disable)**:
   - The EPUB lives in a hidden cache dir inside the KOReader data dir (e.g. `<DataStorage:getDataDir()>/.mecbook/`), never in the user's library/home folder. No export or copy feature.
   - Store the due date locally at download time. Expiry is checked without network: on KOReader start, on resume, **before a book opens** (an expired book must never open), and via a local timer while KOReader is running. Changing the Kindle clock is an accepted loophole.
   - With Wi-Fi, a rental no longer active on the server (returned on the website) also triggers deletion.
   - No early return: the platform only accepts a return at the end of the term, so the book is removed when the loan expires (or is gone from the server).
5. **Progress survives deletion**: before deleting, archive the book's KOReader metadata (progress, highlights, notes) keyed by book id; restore it when the same book is borrowed again, before opening. Respect the user's sidecar location setting (doc / dir / hash); verify the right `DocSettings` API in KOReader's source. Remove the dead entry from reading history.
6. **Deterministic EPUB**: same input manifest → byte-identical EPUB (fixed entry order, fixed timestamps, `mimetype` stored first). Keeps annotation positions valid and keeps KOReader statistics (keyed by partial MD5) attached to the same book. Verify `ffi/archiver` can set mtimes; otherwise write the zip another way.
7. **User notices**: warn N days before expiry (default 3) on start/resume. On removal: explain why, show where she stopped (chapter / %), offer to borrow again (or join the queue if the API supports it; the original has no queue endpoint).
8. **Disclaimer** in README and on first run: not affiliated with MEC; not a piracy tool and not for redistribution; only accesses active loans of the user's own account; each user uses their own account at their own risk; MEC may block access at any time.
9. **Token safety**: never log tokens, headers or URLs carrying secrets. Store tokens in plugin settings; import them from a `mecbook_tokens.lua` file in `koreader/settings/` like the original (then delete or blank the file). Ship only a `.sample` file; gitignore the real one.

## Architecture

Pure Lua core, thin KOReader shell:

- `api/` HTTP client with an injected transport (real one wraps `socket.http`; tests use a fake). Handles UA, auth header, refresh-on-401, 403-stop, backoff.
- `loans/` loan manager: state of the current loan, due-date logic, expiry decisions, sync with server state. Takes a clock and a filesystem adapter as dependencies.
- `epub/` manifest → EPUB builder, deterministic.
- `storage/` hidden cache paths, metadata archive/restore.
- `ui/` KOReader widgets, menus and event handlers (`onResume`, reader-ready hook, timers). No business logic here.
- `main.lua` wires everything.

## Repository layout

```
mecbook.koplugin/   # the shippable plugin folder (_meta.lua, main.lua, modules)
spec/               # busted tests + fixtures (redacted real responses)
scripts/deploy.sh   # copies mecbook.koplugin/ to /d/koreader/plugins/
.luacheckrc
README.md  LICENSE  .gitignore
```

`_meta.lua`: `name = "mecbook"`, `fullname = "MECBook"`, description in pt-BR.

## Testing

- busted for unit tests, luacheck for lint. Run both after every change.
- Fixtures for every API shape; never hit the real API in tests.
- Priority test targets: expiry decisions (boundaries, timezone, clock), sync with server state, 401 refresh / 403 stop / backoff, deterministic EPUB (build twice, compare bytes), metadata archive/restore.
- Plan a GitHub Actions workflow (luacheck + busted on LuaJIT). The org may later host a reusable workflow in `shiori-koreader/.github`.

## Suggested order

1. Repo skeleton, LICENSE (MIT, both copyrights; ask Thiago for his name line), README with disclaimer, luacheck + busted setup.
2. Pure modules with tests: loan/expiry logic, storage paths, deterministic EPUB builder.
3. API client with fake transport and tests.
4. First real call with Thiago's token: `auth/me` and `rentals`, save redacted fixtures, confirm the due-date field and that the UA is accepted.
5. KOReader UI and event wiring; manual test on the Kindle via `scripts/deploy.sh`.

## Open questions

- Login without copying tokens from DevTools.
- Whether the API has a waitlist/queue endpoint.
- Exact `rentals` response shape.
- KOReader version on the device.
- Read the platform's terms of use (behind login) before the first public release.
