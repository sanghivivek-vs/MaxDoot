# Public Site setup — exposing the MaxDoot inbound webhook

heydoot needs to POST inbound WhatsApp messages to Salesforce. Apex REST normally
requires a login, so MaxDoot ships a **Force.com Site** that exposes
`MaxDootInboundResource` to the Site **guest user** with no Salesforce session —
security is enforced by the `X-MaxDoot-Token` header.

This bundle lives in two **separate package directories** so it never blocks the
core app deploy:

```
salesforce/site/         CustomSite + Visualforce index page
salesforce/site-guest/   the guest-user profile that grants access
```

> If you'd rather not run a public Site, use the **OAuth** alternative in the
> root README instead (heydoot obtains a Salesforce token and calls the
> `*.my.salesforce.com` REST URL). You can ignore this whole bundle in that case.

---

## Prerequisites (one-time, in Setup)

1. **My Domain** must be deployed (Setup → My Domain).
2. **Sites** must be enabled and a **site domain registered**:
   Setup → Sites → accept terms → register a domain (e.g.
   `https://mycompany.my.salesforce-sites.com`). The chosen prefix is your
   `subdomain`.

---

## Edit the placeholders

In `salesforce/site/main/default/sites/MaxDoot_Inbound.site-meta.xml`:

| Placeholder                   | Set to                                                        |
| ----------------------------- | ------------------------------------------------------------- |
| `REPLACE_WITH_ADMIN_USERNAME` | an active admin/integration **username** (site + guest owner) |
| `REPLACE_WITH_SITE_SUBDOMAIN` | your registered site domain prefix                            |
| `urlPathPrefix` (`maxdoot`)   | the path segment for the site (keep `maxdoot` or change)      |

---

## Deploy order (two steps — important)

The guest profile only exists **after** the Site is created, so deploy the Site
first, then the guest profile.

```bash
# from salesforce/
# 1) deploy the core app first (if not already)
sf project deploy start -d force-app -o <org>

# 2) deploy the Site + index page  (creates the guest user + "MaxDoot Inbound Profile")
sf project deploy start -d site -o <org>

# 3) deploy the guest profile grant
sf project deploy start -d site-guest -o <org>
```

If step 3 errors with “unknown profile”, the guest profile name didn’t match.
Confirm the exact name at Setup → Sites → **MaxDoot Inbound** → Public Access
Settings (the profile is `<Site Label> Profile`), rename the file to match, and
re-run step 3. You can always grant the access manually instead (below).

---

## Manual fallback (if the profile deploy is fiddly)

Setup → Sites → **MaxDoot Inbound** → **Public Access Settings**:
- **Enabled Apex Class Access** → add `MaxDootInboundResource`.
- **Enabled Visualforce Page Access** → add `MaxDootSiteHome`.
- Object Settings → **MaxDoot Inbound** (platform event) → allow **Create**.

---

## Your webhook URL

After the Site is active, the inbound endpoint heydoot should POST to is:

```
https://<your-site-domain>/maxdoot/services/apexrest/maxdoot/inbound
```

(`<site-domain>` is your registered domain; `maxdoot` is the `urlPathPrefix`.)

Configure heydoot to send:
- Method: `POST`
- Header: `X-MaxDoot-Token: <MaxDoot_Config__mdt.Default.Inbound_Token__c>`
- Body: the inbound event JSON (see root README).

Verify with curl:

```bash
curl -i -X POST \
  "https://<your-site-domain>/maxdoot/services/apexrest/maxdoot/inbound" \
  -H "Content-Type: application/json" \
  -H "X-MaxDoot-Token: <your-token>" \
  -d '{"type":"message","channelId":"chan-1","from":"+19998887777","to":"+10000000000","messageId":"test-1","body":"hello"}'
```

A `200 {"accepted":1}` means the event was published; a `WC-…` conversation and
`WM-…` message should appear in the MaxDoot app shortly after.
