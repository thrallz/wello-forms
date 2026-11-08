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

### Phase 2 — User roles
Open-source DocuSeal ships a single `admin` role (`User::ROLES`). Add:

| Role | Can |
|---|---|
| `admin` | Everything, settings, users, integrations |
| `manager` | All templates & submissions for their team, approve, reassign |
| `employee` | Create/send from assigned templates, see own submissions |
| `client` | Client portal only — their own documents to sign / download |

Implement via `User::ROLES`, the CanCanCan `Ability` class (`lib/ability.rb`), and a `team_id` on users/submissions.

### Phase 3 — Client dashboard, employee workflow, document history
- **Client dashboard** (`/portal`): pending to sign, completed (download), history; magic-link or password login.
- **Employee workflow**: queue of submissions by status (draft → sent → viewed → signed → reviewed → filed), assign/reassign, internal notes, reminders.
- **Document history**: unified timeline per document and per client from `submission_events` (sent, opened, signed, declined, downloaded) + Wello workflow events; export audit trail PDF.

### Phase 4 — Vtiger integration
Vtiger's built-in **Esign Documents** module only talks to DocuSign / Zoho Sign, so Wello Forms can't be plugged in as a native provider. Integrate through Vtiger workflows + REST API instead:

1. **Vtiger → Wello Forms (send):** a Vtiger workflow (e.g. Deal stage = "Contract", or a checkbox "Send for signature") with a **Webhook** action POSTs the record to `POST /api/wello/vtiger/webhook`. Wello Forms maps the record to a template, prefills fields, creates the submission and emails the signer.
2. **Wello Forms → Vtiger (status):** on `form.viewed`, `form.completed`, `form.declined`, update the Vtiger record (custom fields `Wello Sign Status`, `Wello Sign Link`, `Signed On`) via the Vtiger REST API.
3. **Signed PDF back to CRM:** on completion, upload the signed PDF + audit log as a Vtiger Document linked to the Contact/Organization/Deal.
4. Store mapping (Vtiger module + record ID ↔ submission ID) in a `wello_crm_links` table so the history view can link back to the CRM.

Build the CRM layer behind an adapter (`Wello::Crm::VtigerAdapter`) so a `SuiteCrmAdapter` can be added later without touching the signing flow.

Config (`.env`): `VTIGER_URL`, `VTIGER_USERNAME`, `VTIGER_ACCESS_KEY` (user preferences → access key).
