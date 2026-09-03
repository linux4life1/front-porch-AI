# Web & Phone

Your **desktop app is the brain**. The browser on your phone is a window into it. The desktop must stay on.

This is **not** a clone of every desktop button.

---

## Turn it on

1. Desktop: Settings → **Advanced** → **Web Server** → **Enable Web Server**.
2. Same Wi-Fi: open `http://<that-computer>:8085`.
3. First visit: create a web username and password.
4. Not localhost (phone, another PC, a tunnel): also type the **one-time setup code** from that same Settings page.

QR code is on that page. **Remote** on the phone is its own screen: Tailscale login, HTTPS, optional **ngrok**, QR — not only the desktop wizard.

**Away from home:** Tailscale (recommended). Nothing exposed to the public internet.

**Security:** optional 2FA (QR + recovery codes). Turning 2FA on or off asks for the web password. Desktop can **sign out all devices** or **reset the web login** (clears web user/pass/2FA only — not characters). Dangerous Account actions re-ask the web password.

Mic / push-to-talk on a phone needs **HTTPS** (Tailscale HTTPS or similar). Plain `http://192.168…` will **refuse** the microphone.

Add to Home Screen: Android may show a banner. iPhone: Share → Add to Home Screen.

---

## What works on the phone

Chats (including groups), library and editors, AI create, models (including **generate a picture** and insert), settings (one scrolling page, not six tabs), Worlds, Porch Stories, browsing The Stoop (download, follow, vote, comments if your email is confirmed).

Push-to-talk mic over HTTPS. Impersonate, fork, swipes, `/image`.

---

## Desktop only

Do these on the Mac/PC app:

- Full **Image Studio** (Create / Edit / LoRA / expression-pack QC)
- **Voice Call** (green call button, call model, buffer, call prompt)
- **Suggest Actions**
- **Attach a photo** / Photo Understanding
- Stoop **upload / share** (the phone Share tab is not a live uploader)
- Backups & Restore
- Database Scan & Clean / change data folder
- Turn Into a Story from chat
- Director auto-play + response delay (toggle exists; pacing is desktop)
- Custom Piper voice importer
- GPU launch, Flash Attention, `.kcpps`, six-tab Settings layout

---

## Two computers

There is **no** cloud sync. Copy the `FrontPorchAI` folder, or leave the library on one machine and use this web server from the other.

FAQ: [Chat from my phone](faq.md#chat-from-my-phone) · [What's missing](faq.md#whats-missing-on-the-phone).
