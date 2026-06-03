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
```

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

---

## Configure the heydoot link (post-deploy)

1. **Named Credential** — Setup → Named Credentials → `heydoot`: set the URL to
   your heydoot base URL. (For production auth, migrate this to an External
   Credential principal instead of the API-key field below.)
2. **MaxDoot Config** (`MaxDoot_Config__mdt`, record `Default`):
   - `Api_Key__c` — bearer token sent to heydoot on outbound calls.
   - `Inbound_Token__c` — shared secret heydoot must send in the
     `X-MaxDoot-Token` header.
   - `Send_Path__c`, `QR_Path__c`, `Status_Path__c` — adjust to heydoot's real
     endpoints (defaults assume `/v1/channels/{channelId}/...`).
3. **heydoot webhook** — point heydoot's inbound webhook at:
   `https://<your-domain>/services/apexrest/maxdoot/inbound`
   with header `X-MaxDoot-Token: <Inbound_Token__c>`.
4. **Create a Channel** (`Channel__c`): set `Heydoot_Channel_Id__c`, the WhatsApp
   number, and `Scope` (Org/Team/Agent). Open the **MaxDoot** app → **Channels**
   tab → select the channel → **Load QR** → scan with the WhatsApp phone.

---

## heydoot API contract (to confirm)

The exact payloads are configurable; current assumptions:

| Direction | Method & path                                   | Notes                              |
| --------- | ----------------------------------------------- | ---------------------------------- |
| Send      | `POST {base}/v1/channels/{channelId}/messages`  | `{to, type, text?, mediaUrl?}`     |
| QR        | `GET  {base}/v1/channels/{channelId}/qr`        | returns `{qr}` or a data-URL/string |
| Status    | `GET  {base}/v1/channels/{channelId}/status`    | returns `{status}`                 |
| Inbound   | `POST /services/apexrest/maxdoot/inbound`       | heydoot → Salesforce, token header |

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
