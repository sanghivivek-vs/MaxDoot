# MaxDoot

WhatsApp conversations **inside Salesforce**, powered by the existing **heydoot**
engine — without Salesforce Messaging for WhatsApp (Digital Engagement) licensing.

- **Native Salesforce UI** — a Lightning app + tab built with LWC/SLDS:
  inbox, conversation thread, dashboard, and in-Salesforce **QR login**.
- **heydoot is the engine** — MaxDoot calls heydoot's API to send, and heydoot
  webhooks Salesforce on inbound. Works with or without the WhatsApp Business API
  (whatever heydoot is configured for).
- **Per-team / per-agent / org-wide** routing via a configurable `Channel__c`.
- **Single-org deploy** — no managed package, no namespace.

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full framework.

---

## What's in here

```
salesforce/force-app/main/default/
  objects/        Channel__c, Conversation__c, Message__c, MaxDoot_Inbound__e (PE), MaxDoot_Config__mdt
  classes/        Apex: inbound webhook, PE handler, send/channel/dashboard controllers, heydoot client, routing, tests
  triggers/       MaxDootInboundTrigger (persists platform events)
  lwc/            maxdootConsole, maxdootInbox, maxdootConversation, maxdootDashboard, maxdootChannelSetup
  namedCredentials/  heydoot (base URL)
  customMetadata/    MaxDoot_Config.Default (paths, API key, inbound token)
  permissionsets/    MaxDoot_Agent, MaxDoot_Admin
  applications/ tabs/ flexipages/   MaxDoot app + tab + console page
  cspTrustedSites/   heydoot (allow QR iframe + connections)

salesforce/site/        Force.com Site + Visualforce index (public webhook host)
salesforce/site-guest/  guest-user profile granting webhook access
```

The `site` / `site-guest` directories are **separate package dirs** — the core
app deploys on its own; deploy the Site bundle only if you use the public-Site
webhook option (see [`docs/SITE_SETUP.md`](docs/SITE_SETUP.md)).

> **Status:** first end-to-end implementation. It was authored without a live org
> to compile against, so treat the first deploy as a shakeout — minor
> environment-specific fixes may be needed.

---

## Deploy

```bash
# from the salesforce/ directory
sf project deploy start -d force-app -o <your-org-alias>

# run the Apex tests
sf apex run test -o <your-org-alias> -l RunLocalTests -w 10
```

Then assign a permission set:

```bash
sf org assign permset -n MaxDoot_Agent -o <your-org-alias>
sf org assign permset -n MaxDoot_Admin -o <your-org-alias>   # for setup / integration user
```

For the public inbound webhook host, deploy the Site bundle separately — see
[`docs/SITE_SETUP.md`](docs/SITE_SETUP.md).

---

## Configure the heydoot link (post-deploy)

1. **Named Credential** — Setup → Named Credentials → `heydoot`: set the URL to
   your heydoot base URL.
2. **CSP Trusted Site** — Setup → CSP Trusted Sites → `heydoot`: update the
   endpoint to your heydoot domain (required for the QR iframe to render).
3. **MaxDoot Config** (`MaxDoot_Config__mdt`, record `Default`):
   - `Inbound_Token__c` — shared secret heydoot must send in the
     `X-MaxDoot-Token` header on inbound webhooks.
   - `Send_Path__c`, `QR_Path__c`, `Status_Path__c` — adjust to heydoot's real
     endpoints (token-scoped defaults: `/v1/messages`, `/v1/qr`, `/v1/status`).
   - `Api_Key__c` — optional global fallback token (per-channel tokens below are
     preferred).
4. **Create a Channel per WhatsApp number** (`Channel__c`):
   - `Bearer_Token__c` — **the heydoot bearer token for that number/session**
     (this is how MaxDoot addresses multiple numbers).
   - `WhatsApp_Number__c` — used to match inbound messages back to the channel.
   - `Scope` — Org / Team / Agent (+ `Assigned_Agent__c` when Agent).
   - `Iframe_QR_URL__c` — optional; heydoot's embeddable login/QR page URL.
5. **Connect the number** — open the **MaxDoot** app → **Channels** → select the
   channel. If `Iframe_QR_URL__c` is set, the heydoot login page renders inline
   (scan it); otherwise click **Load QR** (API fallback). Use **Refresh Status**
   to confirm `Connected`.
6. **heydoot webhook** — point heydoot's inbound webhook at the endpoint below
   with header `X-MaxDoot-Token: <Inbound_Token__c>`.

### Exposing the inbound webhook endpoint

heydoot needs to POST to Salesforce. The Apex REST path is:

```
/services/apexrest/maxdoot/inbound
```

Salesforce Apex REST normally requires an authenticated session, so pick one:

- **Public Site (recommended, scaffolded):** a Force.com **Site** that exposes
  `MaxDootInboundResource` to the Site **guest user** is included under
  `salesforce/site/` + `salesforce/site-guest/`. heydoot POSTs to
  `https://<your-site-domain>/maxdoot/services/apexrest/maxdoot/inbound`
  with no Salesforce login — the `X-MaxDoot-Token` header is the security
  boundary. **See [`docs/SITE_SETUP.md`](docs/SITE_SETUP.md)** for prerequisites,
  placeholders to edit, and the two-step deploy order.
- **OAuth:** create a Connected App; heydoot obtains a Salesforce access token
  (JWT/client-credentials) and calls
  `https://<MyDomain>.my.salesforce.com/services/apexrest/maxdoot/inbound`
  with both the SF bearer token and the `X-MaxDoot-Token` header.

> The Site approach is simpler for heydoot to integrate; the token header is the
> security boundary, so keep `Inbound_Token__c` strong and rotate it.

---

## heydoot API contract (confirmed + to pin)

Auth is a **per-number bearer token** (stored on each `Channel__c`). Paths are
configurable; current assumptions:

| Direction | Method & path               | Auth                    | Notes                               |
| --------- | --------------------------- | ----------------------- | ----------------------------------- |
| Send      | `POST {base}/v1/messages`   | `Bearer <channel tok>`  | `{to, type, text?, mediaUrl?}`      |
| QR        | iframe `Iframe_QR_URL__c`, or `GET {base}/v1/qr` | `Bearer <channel tok>` | iframe preferred |
| Status    | `GET  {base}/v1/status`     | `Bearer <channel tok>`  | returns `{status}`                  |
| Inbound   | `POST /services/apexrest/maxdoot/inbound` | `X-MaxDoot-Token` header | heydoot → Salesforce |

Inbound webhook body (single event or `{events:[...]}`):

```json
{
  "type": "message",
  "channelId": "chan-1",
  "from": "+19998887777",
  "to": "+10000000000",
  "messageId": "hd-1",
  "body": "Hello",
  "mediaUrl": null,
  "timestamp": "2026-06-03T10:00:00Z"
}
```

Status events use `"type":"status"` with `messageId` + `status`
(`sent|delivered|read|failed`).
