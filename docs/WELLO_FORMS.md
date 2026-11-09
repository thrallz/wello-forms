# Wello Forms

Wello Payment's document-signing portal, built on a fork of [DocuSeal](https://github.com/docusealco/docuseal).

## Branches

| Branch | Purpose |
|---|---|
| `master` | Mirror of upstream DocuSeal. Never commit here; sync with GitHub's **Sync fork** button. |
| `wello-main` | Wello Forms product branch. Merge `master` into it after each upstream sync. |
| `feature/*` | Work branches, merged into `wello-main` via pull request. |

Keeping Wello changes isolated (new files, `wello` namespaces, small hooks into upstream code) makes upstream merges painless.

## Licensing — read before rebranding

DocuSeal is **AGPL-3.0** with an additional term (`LICENSE_ADDITIONAL_TERMS`):
a covered work must **retain the original DocuSeal attribution in interactive user interfaces**.

What that means for Wello Forms:

- ✅ Wello Payment logo, colors, product name, emails, custom domain, custom dashboard — all fine.
- ⚠️ Keep the small "Powered by DocuSeal" attribution (`app/views/shared/_powered_by.html.erb`, `_attribution.html.erb`). Restyle it, don't remove it.
- ⚠️ AGPL: anyone who uses the hosted app over a network must be able to get the modified source. Keep this repo public (it is, as a fork of a public repo) or provide a source link in the footer.
- Removing attribution entirely requires a commercial license from DocuSeal (DocuSeal Pro / Enterprise).
- Not legal advice — have counsel confirm before launch.

## Development environment (Docker host / Portainer)

Requirements on the server: Docker Engine + Compose v2, ~4 GB RAM free, port 3000 open to your LAN.

```bash
# On the Docker host (SSH)
git clone -b wello-main https://github.com/thrallz/wello-forms.git
cd wello-forms
cp .env.example .env
sed -i "s/^SECRET_KEY_BASE=.*/SECRET_KEY_BASE=$(openssl rand -hex 64)/" .env
docker compose -f docker-compose.dev.yml up -d --build
docker compose -f docker-compose.dev.yml logs -f app   # first boot installs gems + JS (5–10 min)
```

Then open `http://<server-ip>:3000` and create the first admin account.

| URL | What |
|---|---|
| `:3000` | Wello Forms (Rails, auto-reloads Ruby/ERB changes) |
| `:3000/letter_opener` | Outgoing emails captured in dev (nothing is really sent) |
| `:3000/sidekiq` | Background jobs (admin only) |

**Editing code:** use VS Code → *Remote-SSH* into the Docker host and open the `wello-forms` folder. The source is bind-mounted into the containers, so saves are live. Vue/JS changes recompile via the `webpacker` container.

**Portainer:** Stacks → Add stack → Repository → URL `https://github.com/thrallz/wello-forms`, reference `refs/heads/wello-main`, compose path `docker-compose.dev.yml`, and add `SECRET_KEY_BASE` under environment variables. Good for a shared preview; for day-to-day coding use the SSH clone above so you can edit files.

Useful commands:

```bash
docker compose -f docker-compose.dev.yml exec app bin/rails console
docker compose -f docker-compose.dev.yml exec app bin/rails db:migrate
docker compose -f docker-compose.dev.yml exec app bundle exec rspec
docker compose -f docker-compose.dev.yml down          # stop (data kept)
docker compose -f docker-compose.dev.yml down -v       # stop and wipe DB/gems
```

## Roadmap

### Phase 1 — Branding (Wello Payment)
- Product name / logo: `Docuseal.product_name`, `app/views/shared/_logo.html.erb`, favicons in `public/`.
- Theme colors in `tailwind*.config.js` (daisyUI theme).
- Email templates and sender name; signing-page header logo.
- Restyle (keep) DocuSeal attribution — see Licensing.

### Phase 2 — User roles ✅ (branch `feature/roles`)

| Role | Templates | Documents (submissions) | Settings |
|---|---|---|---|
| `admin` | All | All | Everything, users, teams |
| `manager` | Use all; create; edit/delete own team's | Own team's | Own profile |
| `employee` | Use all; create; edit/delete own | Own only | Own profile |
| `client` | — | Client portal (`/portal`): documents sent to their email | Own profile |

- Teams: Settings → Teams (admins). Assign role + team when adding/editing a user.
- A manager with no team sees only their own documents.
- Documents created by API/automation (no creator) are visible to admins only.
- Code: `lib/ability.rb` (rules), `app/models/wello_team.rb`, `app/controllers/concerns/wello_client_access.rb`, `app/controllers/wello_portal_controller.rb`.
- Tests: `docker compose -f docker-compose.dev.yml exec app bin/wello-spec spec/lib/wello_ability_spec.rb spec/requests/wello_roles_spec.rb`

### Phase 3 — Clients, send flow, document history ✅ (branch `feature/clients`)

- **Clients** (top bar → Clients): search by business name, contact, email, phone digits or MID; add/edit/archive.
  Fields: DBA, legal name, contact first/last, email, phone, MID, address, notes, assigned rep, Vtiger link.
  Visibility follows the roles: employees see clients assigned to them, managers their team's, admins all.
- **Send a form** (client page or the Send button in the list): pick a template → choose which role the client
  signs as → optional other signers (defaults to you) → email and/or SMS → pre-fill → Send.
- **Auto-fill:** text fields whose name matches client data are pre-filled. Recognised names include
  `Business Name`, `DBA`, `Legal Name`, `Name`, `Owner Name`, `First Name`, `Last Name`, `Email`, `Phone`,
  `MID`, `Merchant ID`, `Address`, `Suite`, `City`, `State`, `ZIP`, `Full Address` (case/punctuation ignored).
  Rename fields in the template builder to use this.
- **Document history:** each client page lists *In progress* and *Signed documents* with per-signer status;
  every document sent from the client flow is linked to the client (`submissions.wello_client_id`).

### Phase 4 — SMS, email, Vtiger ✅ (branch `feature/clients`)

**Email (your SMTP):** Settings → Email. Built into DocuSeal; enter host, port, username, password, from address.

**SMS (your Twilio):** Settings → SMS → Account SID, Auth Token, and a From number (`+15551234567`) or a
Messaging Service SID (recommended for US A2P 10DLC). Use *Send a test SMS* to verify. Once connected:
- the send flow offers SMS; links also go out by SMS through the API (`send_sms: true`) and to the next signer
  in ordered signing; submission pages get *Send / Re-send SMS*;
- each SMS is logged as a `send_sms` event in the document's audit trail.

**Vtiger (Cloud):** Settings → Vtiger → URL (`https://yourcompany.od2.vtiger.com`), username and access key
(Vtiger → My Preferences), optional MID custom field name (e.g. `cf_accounts_mid`). Save tests the connection.
- **Import from Vtiger** (Clients page): search organizations, contacts and leads by name, email, phone or
  record number, then *Import & send*. Works on every Vtiger edition.
- **Link on Vtiger records (classic Vtiger / any edition):** Settings → Module Layouts & Fields → Organizations →
  add a URL custom field "Wello Forms". Settings → Workflows → new workflow for Organizations, *every time the
  record is saved*, action *Update Fields*: Wello Forms = expression
  `concat('https://<wello-forms-host>/vtiger/open?module=Accounts&number=', account_no)`
  (Contacts: `module=Contacts` + `contact_no`; Leads: `lead_no`; Deals: `module=Potentials` + `potential_no`).
  Existing records get the link when next saved (use Mass Edit to save many). Settings → Vtiger in Wello Forms
  shows the exact expressions with your server address.
- **Button in Vtiger (One Professional/Enterprise only):** Menu → Platform → Module Designer → UI Actions → *Detail View Basic Button* for
  Organizations / Contacts / Leads / Deals, click action:
  `window.open('https://<wello-forms-host>/vtiger/open?module=' + VTAP.Detail.Module() + '&record=' + VTAP.Detail.Id(), '_blank');`
  Clicking it imports/refreshes the client in Wello Forms (contacts and deals are filed under their organization)
  and opens *Send a form*. Add `&template_id=<id>` to pre-select a template.
- **Sync from Vtiger** button on linked client pages refreshes details.
- **Wello Signatures (DocuSign/Zoho Sign-style tracking in Vtiger):** create a custom module once with
  Vtiger *Settings → Module Builder*, and Wello Forms keeps a sign-request record per document with live status
  and puts the signed copy in the record's Documents tab. See *Vtiger: Wello Signatures module setup* below.
  Without the module, a comment with a link is posted on the record when a document is signed.
- Code is behind `Wello::Vtiger` so a SuiteCRM connector can be added later.

### Vtiger: Wello Signatures module setup

In Vtiger: **Settings → Module Builder → Create New Module**.

1. **Module Properties**
   - Module Label: `Wello Signatures` · Singular Module Label: `Wello Signature`
   - App Category: *Sales* (or wherever your team works) · Record Identifier: `Document Name`
2. **Blocks and Fields** — add these fields (labels must match; case doesn't matter):

   | Label | Type | Notes |
   |---|---|---|
   | `Status` | Picklist | Values exactly: `Sent`, `Viewed`, `Signed`, `Declined` |
   | `Signer Name` | Text | |
   | `Signer Email` | Email | |
   | `Sent On` | Date | |
   | `Signed On` | Date | |
   | `Document Link` | URL | Opens the document in Wello Forms (the signed copy once complete) |

3. **Default Filter** — show Document Name, Status, Signer Name, Sent On, Signed On.
4. **Relationships** — add a relationship with **Organizations** (one Organization has many Wello Signatures).
   Optionally also Contacts, Leads and Deals. This adds the *Wello Signatures* tab on those records.

Then in Wello Forms: **Settings → Vtiger** → the *Wello Signatures module* panel should show the module and a
green tick for every field. Fields with a red cross were not found — check the label spelling in Vtiger.

What happens after that, for documents sent to a client linked to Vtiger:

| Event in Wello Forms | In Vtiger |
|---|---|
| Form sent | New Wello Signature record, Status = Sent, linked to the organization |
| Signer opens it | Status = Viewed |
| Signer declines | Status = Declined |
| Everyone signs | Status = Signed, Signed On set, Document Link → signed copy; a *Signed: …* entry is added to the organization's Documents tab |

### Next ideas
- SuiteCRM connector (same interface as `Wello::Vtiger`).
- Employee work queue across clients (sent → viewed → signed → reviewed → filed) with reminders.
- Upload the signed PDF file itself into Vtiger Documents (today it's a web link to the signed copy).

## Testing

GitHub Actions runs RuboCop, ERB lint, ESLint, Brakeman and the full RSpec suite on every push
(Actions tab on GitHub). Locally on the dev server:
`docker compose -f docker-compose.dev.yml exec app bin/wello-spec spec/lib/wello spec/requests/wello_clients_spec.rb`

## Brand palette (Phase 1)

| Name | Hex | Use |
|---|---|---|
| Wello Orange | `#F7991F` | Logo, highlights, badges (daisyUI `secondary`) |
| Charcoal | `#1F2328` | Main buttons, body text (`neutral`, `base-content`) |
| White | `#FFFFFF` | Page background (`base-100`) |
| Deep Teal | `#0E7490` | Accent: links, info, completed states (`accent`) |
| Orange Tint | `#FDE7CC` | Soft buttons, filter chips (`primary`) |
| Dark Orange | `#B45309` | Orange text on white (readable contrast) |

Use charcoal text on orange; white on orange is too low-contrast. Logo files: `public/wello/`. Brand constants: `lib/wello.rb`. Preview: `docs/wello-brand-sheet.png`.
