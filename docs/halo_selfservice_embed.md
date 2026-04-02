# Halo Self Service Portal Custom HTML (Embedded ITSM UI)

This guide explains how to embed the ITSM chat UI into the Halo Self Service Portal using custom HTML.

Use this document as the single source of truth for portal embed setup from both:
- `docs/deployment_Steps.md`
- `docs/manual_deployment.md`

---

## 1. Prerequisites

Collect the following values first:

| Value | Source |
|---|---|
| UI URL | Terraform output `container_app_ui_url` or Azure Portal -> Container App (UI) |
| API URL | Terraform output `container_app_url` or Azure Portal -> Container App (API) |

Expected format:
- UI URL: `https://<ui-app>.<region>.azurecontainerapps.io`
- API URL: `https://<api-app>.<region>.azurecontainerapps.io`

---

## 2. Start From the Template

Use the repository template file:

- `halo_serlfservice_custom.html`

This file contains:
- A floating chat bubble launcher
- An iframe-based embedded chat experience
- Responsive behavior for desktop and mobile

---

## 3. Update the iframe URL

In `halo_serlfservice_custom.html`, find the iframe `src` and replace it with your deployed endpoints:

```html
src="https://<ui-url>/embed.html"
```

Example:

```html
src="https://itsm-ui.contoso.eastus2.azurecontainerapps.io/embed.html"
```

Notes:
- Keep `/embed.html` on the UI URL.
- The embedded React UI calls `/chat` relative to the UI origin.
- API routing is handled by the UI container's nginx proxy (`API_URL` environment setting), not an `api=` query string.
- Ensure `API_URL` for the UI container points to your deployed ITSM API service.

---

## 4. Disable Halo Native Chat Bubble

Before enabling the embedded widget, disable Halo's built-in chat bubble to avoid duplicate floating chat launchers.

In Halo (admin):

1. Open **Configuration -> Chat**.
2. Under **Agent chat settings**, locate **New live chat display**.
3. Change it from **Show a chat bubble for new live chats from users** to a non-bubble option (wording can vary by tenant/version).
4. If enabled in your tenant, clear **Enable Chat for End-Users on the Self-Service Portal**.
5. Save changes.

---

## 5. Add HTML to Halo Self Service Portal

In Halo (admin):

1. Open **Configuration**.
2. Open **Self Service Portal** settings.
3. Locate the **Custom HTML** area.
4. Paste the full contents of `halo_serlfservice_custom.html`.
5. Save and publish portal changes.

If your Halo tenant uses different menu labels, follow the equivalent Self Service branding/customization path and apply the same HTML in the custom markup area.

---

## 6. Validate Behavior

Open the Self Service Portal and verify:

1. Chat bubble is visible in the lower-right corner.
2. Clicking bubble opens the embedded chat frame.
3. Chat loads and can send/receive messages.
4. Embedded image content renders correctly inside responses.
5. "New conversation" icon appears at the top-left in the embed header.
6. On mobile widths, the chat expands to near full-screen and remains usable.
7. No separate Halo-native chat bubble appears.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Chat frame stays blank | Incorrect UI URL in iframe `src` | Recheck the UI URL and use `/embed.html` |
| Requests fail in embed | Wrong API URL or API unavailable | Confirm API container app is running and URL is correct |
| Bubble shows but does not open | HTML partially pasted or script/style stripped by portal | Re-paste the full template and ensure custom HTML is allowed |
| Two chat bubbles appear | Halo native chat bubble still enabled | In **Configuration -> Chat**, set **New live chat display** to a non-bubble option and save |
| Close button overlaps host controls | Host portal CSS conflicts | Keep latest template from repo; adjust only if tenant theme requires it |
| Images missing in responses | Older UI build deployed | Redeploy latest UI container image |

---




