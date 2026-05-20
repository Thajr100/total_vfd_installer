# Total VFD — Easy Odoo installer

Friendly shell helper for **installing** or **updating** the Total VFD Odoo module on your server. Works with **Docker** and **normal (non-Docker)** Odoo setups.

No Odoo coding knowledge required — answer the questions, then finish in the Odoo web app (Install or Upgrade).

---

## What you need

- **SSH access** to the machine that runs Odoo (or run the script on that machine).
- A **download link** to `total_vfd.zip` from your vendor (HTTPS recommended).
- **sudo** may be needed on non-Docker installs (restart service, file permissions).

---

## Quick start

```bash
# 1) Copy this folder to the Odoo server (or clone this repo)
cd total_vfd_installer

# 2) Run the installer
chmod +x install-total-vfd.sh
./install-total-vfd.sh
```

Optional: set a default zip URL so you are not asked every time:

```bash
cp config.example.env .env
# Edit .env → DEFAULT_ZIP_URL=https://...
./install-total-vfd.sh
```

---

## What the script does

| Action | Install | Update |
|--------|---------|--------|
| Downloads `total_vfd.zip` from your URL | Yes | Yes |
| Puts `total_vfd/` in the Odoo addons folder | Yes | Yes (replaces old files) |
| Fixes folder ownership (Docker or Linux user) | Yes | Yes |
| Restarts Odoo (container or system service) | Yes | Yes |
| Installs optional Python packages for QR images | Optional menu | Optional menu |

**It does not** click Install/Upgrade inside Odoo — you still do that once in the browser (the script prints exact steps).

---

## After the script finishes (Odoo web app)

1. Log in as **Administrator**.
2. **Settings** → enable **Developer mode** (if not already on).
3. **Apps** → **Update Apps List**.
4. Search **Total VFD Fiscalisation**:
   - First time → **Install**
   - Already installed → **Upgrade**
5. **Do not** use **Apps → Import Module** for this add-on.

---

## Docker vs non-Docker

The script asks which setup you use.

**Docker (typical)**

- Odoo runs in a container (e.g. `odoo`).
- Module path is often `/mnt/extra-addons/total_vfd` inside the container.
- The script can copy the zip into the container and unzip there.

**Non-Docker**

- You provide the **addons directory** on the server (e.g. `/opt/odoo/custom-addons`).
- You choose how to **restart** Odoo (`systemctl`, `service`, or a custom command).

---

## QR code Python packages (optional)

Fiscalisation works without them; **QR images on PDFs** need `qrcode` and `Pillow` in the same Python Odoo uses.

Use menu option **Install QR Python packages** in the script, or ask your host to run:

```bash
# Docker example
docker exec -u root odoo python3 -m pip install --break-system-packages qrcode Pillow
```

---

## Troubleshooting

| Problem | What to try |
|---------|-------------|
| Download fails | Check URL in a browser; use HTTPS; firewall |
| Permission denied | Re-run with correct addons path; use sudo for non-Docker paths |
| Module not in Apps list | Developer mode on → **Update Apps List** |
| `model_total_vfd_…` error | Uninstall any **Import Module** copy; use this installer, then **Install** from Apps |
| Update did not apply | **Upgrade** the app in Apps (not only restart) |

---

## Ship as its own repo

This folder is self-contained. To publish separately:

```bash
cd total_vfd_installer
git init
git add .
git commit -m "Add Total VFD Odoo installer script"
```

Point customers to clone/copy only `total_vfd_installer/` plus your hosted `total_vfd.zip` URL.

---

*For module configuration (license, Total VFD API), see the main **Total VFD** user guide from your vendor.*
