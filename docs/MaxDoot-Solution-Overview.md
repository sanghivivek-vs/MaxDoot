# MaxDoot for Salesforce
## WhatsApp for Counsellor–Student Conversations — Solution Overview

**Prepared for:** Allen
**Prepared by:** HashStudioz
**Status:** Draft for review · Target go-live ~3 weeks

---

## 1. Executive summary

MaxDoot is a native Salesforce solution that lets Allen's **counsellors and centres
hold one‑to‑one WhatsApp conversations with students directly inside Salesforce** —
without ever leaving the Opportunity, Contact, or Lead they are working on.

A single WhatsApp number at the centre can power **many counsellors sending outbound
messages**, while every conversation stays **threaded, owned, encrypted, and fully
governed** by Salesforce sharing rules and guard rails. The underlying WhatsApp
engine ("Heydoot") runs the connection and the rule engine; Salesforce consumes a
**limited, controlled set of capabilities** through a secure API.

This document explains how the system works end‑to‑end and the capabilities it
delivers.

---

## 2. The use case it solves

> **A complete solution for 1‑to‑1 communication between Allen's counsellors / centres
> and students.** *(Capability #1)*

- A student messages — or is messaged by — a counsellor on WhatsApp.
- The conversation appears **inside Salesforce**, attached to the right student
  record, owned by the right counsellor.
- Counsellors reply with text, **emoji**, **attachments** (with image thumbnails),
  and approved templates — all from the Salesforce record page.
- Managers and admins get oversight, routing, and a central tracker.

It replaces scattered personal‑phone conversations with a **governed, auditable,
CRM‑native channel**.

---

## 3. How it works (architecture)

```
        ┌─────────────────────────────┐         Send (REST, action-based)
        │        SALESFORCE            │  ───────────────────────────────────►  ┌──────────────┐
        │                             │                                          │   HEYDOOT     │
        │  • Conversation & Message    │  ◄───────────────────────────────────   │   (engine)    │
        │    records (encrypted)       │     Receive (secure webhook → SF Site)   │               │
        │  • Counsellor chat panel     │                                          │  • WA session │
        │    on Opportunity/Contact/   │                                          │  • Rule engine│
        │    Lead                      │                                          │  • Scan / QR  │
        │  • Routing, ownership,        │                                          │  • Admin /     │
        │    transfer, guard rails     │                                          │    tracker    │
        └─────────────────────────────┘                                          └──────┬───────┘
                                                                                          │
                                                                                   WhatsApp number
                                                                                   at the Centre
                                                                                          │
                                                                                      Students
```

- **Heydoot is the engine.** It holds the WhatsApp session(s) for the centre's
  number, enforces sending rules/rate limits, and exposes an API to Salesforce for
  **both send and receive**. *(Capability #8)*
- **Salesforce is the workspace.** Counsellors work entirely in Salesforce; only a
  **limited, deliberate set of functions** is exposed to it. *(Capability #9)*
- **Outbound:** Salesforce calls Heydoot's send API. **One centre number → many
  counsellors → many outbound messages.** *(Capability #2)*
- **Inbound:** Heydoot posts each student reply to a secure Salesforce endpoint,
  which threads it onto the right conversation and routes it to the right counsellor.

---

## 4. Capabilities at a glance

| # | Capability | How MaxDoot delivers it |
|---|------------|--------------------------|
| 1 | Complete 1‑to‑1 counsellor↔student channel | Native chat on the student's Salesforce record |
| 2 | One centre number, many outbound senders | All counsellors send from the centre's WhatsApp session |
| 3 | A user can only message **their own** customer | Send is gated by Salesforce record ownership/sharing |
| 4 | Sender number hidden + guard rails on content | Number never exposed in SF; allowed/blocked content controlled |
| 5 | Rule engine (today in Heydoot; portable to SF) | Core rules in Heydoot; selected rules can move to Salesforce |
| 6 | Admin oversight / central tracker | Admins use the Heydoot console as the central tracker |
| 7 | Encrypted, secure transfer | Messages encrypted at rest in SF; secure signed transport |
| 8 | Heydoot is the engine, exposing send + receive APIs | Action‑based REST send + signed inbound webhook |
| 9 | Only limited functions exposed to Salesforce | Send, receive, status, QR — nothing more |
| 10 | Scan & connection control in Heydoot admin | IT admin scans/QRs and configures sessions in Heydoot |
| 11 | Counsellor sees only chats they originated + replies | SF sharing scopes visibility to the owner |
| 12 | Chats can be assigned temporarily (user or admin) | Claim / assign on a conversation |
| 13 | Unassigned chats can be assigned to a SF user | Unassigned pool → assign to a counsellor |
| 14 | Transfer like a Lead when a user is unavailable | Re‑owner the conversation to another SF user |
| 15 | Per‑user / active‑monthly‑user business model | Licensed by active monthly SF users |
| 16 | Joint SFDC + Heydoot development for add‑ons | Both sides extended for Allen's requirements |

---

## 5. Who sees what — visibility & ownership

> **Every counsellor sees only the chats they originated and the replies to them.**
> *(Capability #11)*

- Conversations are **owned records** in Salesforce. Standard **Org‑Wide Default =
  Private** plus the role hierarchy means a counsellor sees their own conversations
  (and, for managers, their team's via hierarchy) — and nothing else.
- **Send is gated by ownership** *(Capability #3)*: a counsellor can start a
  WhatsApp conversation **only from a record they own** (their Opportunity / Contact
  / Lead). If it isn't theirs, they cannot send.
- **Inbound auto‑routing:** when a student replies, MaxDoot matches the number to the
  student's Contact/Lead and routes the conversation to **the counsellor who owns
  that customer** — not a shared pool.

---

## 6. Assignment, claiming & transfer

MaxDoot treats a conversation like any other assignable Salesforce work item.

- **Unassigned pool** *(Capability #13):* a reply from an unknown number lands in an
  Unassigned queue; an admin or counsellor can **assign it to a Salesforce user**.
- **Temporary assignment** *(Capability #12):* admins (or the counsellor) can assign
  a chat to a user for a period — e.g. to cover a shift.
- **Transfer like a Lead** *(Capability #14):* if a counsellor is unavailable
  (ad‑hoc or planned leave), they **transfer the conversation to another Salesforce
  user**, exactly like re‑assigning a Lead. The new owner then sees the full thread
  and continues seamlessly.
- **Claim‑on‑reply:** the first agent to answer an unassigned thread automatically
  takes ownership, so the student's future replies route back to them.

---

## 7. Guard rails, sender privacy & rules

> **The number it is sent from is never visible to the counsellor, and guard rails
> govern what can and cannot be sent.** *(Capability #4)*

- **Sender privacy:** counsellors never see or handle the centre's WhatsApp number;
  it is bound to the channel configuration, not exposed in the UI.
- **Content guard rails:** what may be sent (approved templates, allowed message
  types, 24‑hour‑window rules, rate limits) is enforced. Cold‑outreach safety,
  per‑second/minute/hour limits, and batch caps are applied automatically.
- **Rule engine** *(Capability #5):* the rule engine lives in Heydoot today.
  Where Allen needs CRM‑side enforcement, **selected rules can be brought into
  Salesforce** (e.g. who may message whom, approval before send, content checks).

---

## 8. Security & compliance

> **Chats are encrypted and transferred securely.** *(Capability #7)*

- **Encryption at rest:** message bodies and previews are **encrypted in Salesforce**
  and decrypted in‑memory only for the authorised agent.
- **Secure inbound:** Heydoot authenticates to Salesforce with a **shared secret
  header** on every webhook call; unauthenticated calls are rejected.
- **Secure outbound:** Salesforce calls Heydoot over HTTPS using a **per‑channel
  bearer token** that also scopes which number/session may send.
- **Salesforce platform controls:** field‑level security, sharing rules, and audit
  trails apply to all conversation and message data.

---

## 9. Roles & responsibilities

| Role | Where they work | What they do |
|------|------------------|--------------|
| **Counsellor (SF user)** | Salesforce | Message their own students, reply, attach files, transfer chats |
| **Manager / Team lead** | Salesforce | See team conversations (role hierarchy), reassign, oversee |
| **Salesforce Admin** | Salesforce | Assign unassigned chats, configure guard rails/rules brought into SF |
| **IT / Heydoot Admin** | Heydoot console | **Scan / connect numbers (QR), configure sessions, central tracking** *(Capabilities #6, #10)* |

> **Scan and connection control sit in the Heydoot admin** so IT can configure and
> connect the centre's WhatsApp numbers; **admins use Heydoot as a central tracker**
> across all conversations.

---

## 10. What is exposed to Salesforce (by design)

Only a **limited, deliberate** surface is exposed to Salesforce *(Capability #9)*:

- **Send** a message (text / emoji / attachment link) from the centre's session.
- **Receive** inbound messages and delivery/read status via secure webhook.
- **Session status** (connected / needs‑scan) for health display.
- **QR / connect** for first‑time number setup.

Everything else — session management, the full rule engine, scanning, the central
tracker — **stays in Heydoot**, keeping Salesforce clean and the blast radius small.

---

## 11. Current feature set in Salesforce

- Conversational chat panel embedded on **Opportunity, Contact, and Lead** record
  pages — looks and behaves like a familiar messaging thread.
- **Text, emoji, and attachments** (images render as inline **thumbnails**;
  other files appear as secure links).
- Threaded history with delivery/read status and the 24‑hour‑window indicator.
- Ownership, unassigned pool, claim, assign, and **transfer**.
- Real‑time updates (new replies appear live).
- Standalone **MaxDoot inbox** app for power users handling many conversations.

---

## 12. Business model

> **Licensed per user — based on Active Monthly Users in Salesforce.** *(Capability #15)*

- Pricing is **per Salesforce user, by active monthly usage** — Allen pays for the
  counsellors actually using the channel each month.
- Heydoot engine + number capacity is provisioned to match the centre's volume and
  the agreed rate limits.

---

## 13. Roadmap & go‑live

> **Joint development across Salesforce and Heydoot to support Allen's add‑on
> requirements.** *(Capability #16)* — **Approx. 3 weeks to go‑live.**

| Week | Salesforce | Heydoot |
|------|------------|---------|
| **1** | Finalise routing, guard rails, page layouts | Confirm send/receive API, secrets, number scan |
| **2** | Templates, transfer/assignment UX, admin config | Rule‑engine items, profile‑photo (DP) API, media |
| **3** | UAT with counsellors, hardening, training | Load/rate tuning, central tracker for admins |

Add‑on items identified during UAT are delivered on **both sides** as needed.

---

## Appendix A — Heydoot ↔ Salesforce API contract

MaxDoot calls Heydoot's **single action‑based REST endpoint** for outbound, and
Heydoot calls a **signed Salesforce webhook** for inbound.

**Outbound (Salesforce → Heydoot)** — `POST /api/external`

```json
{ "action": "send-message", "sessionId": "<centre session>", "phone": "<student number, digits>", "message": "<text/link>" }
```

**Inbound (Heydoot → Salesforce webhook)** — header `X-MaxDoot-Token: <shared secret>`

```json
{ "type": "message", "channelId": "<session>", "from": "<student number>",
  "to": "<centre number>", "messageId": "<id>", "body": "<text>",
  "mediaUrl": "<optional media link>", "senderName": "<pushName>",
  "timestamp": "<ISO‑8601>" }
```

Other actions used: `action=status` (session health), `action=qr` (connect/scan).

---

## Appendix B — Display Picture (DP / profile photo) — requested enhancement

Allen would like the **student's WhatsApp profile photo** shown next to the chat.
Salesforce can display it, but **Heydoot must supply it** — WhatsApp profile photos
are only retrievable by the connected session. Two supported options:

**Option 1 — include the avatar in inbound events (preferred):** add a
`profilePicUrl` (and optional cached `avatarBase64`) field to each inbound message
webhook:

```json
{ "type": "message", "from": "<number>", "body": "...",
  "senderName": "Ayaan",
  "profilePicUrl": "https://<heydoot-media-host>/avatars/<number>.jpg" }
```

**Option 2 — a dedicated lookup endpoint:**

```
GET /api/external?action=profile-pic&sessionId=<session>&phone=<number>
→ 200 { "ok": true, "phone": "<number>", "profilePicUrl": "https://…", "name": "Ayaan" }
```

**What we need Heydoot to confirm:**
1. The **field name and shape** (`profilePicUrl` URL vs. base64).
2. **Hosting & access** of the image URL (public/signed; lifetime). If external, the
   host must be added to Salesforce **CSP Trusted Sites (img‑src)** to render.
3. **Refresh behaviour** — when a student changes their photo.
4. **Privacy/consent** — whether storing/displaying student photos is permitted under
   Allen's policy (we can display‑only without persisting if required).

Once Heydoot returns a `profilePicUrl`, the Salesforce side is a small change:
capture it on the conversation and render it as the chat avatar (~½ day).

---

*This document describes the intended solution and is subject to refinement during
UAT. Capabilities map to the numbered requirements provided by Allen.*
