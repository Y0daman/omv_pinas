# Setup-checklista: Raspberry Pi 5 + OMV

## 1) Förberedelse

- Flasha Raspberry Pi OS Lite 64-bit (Bookworm)
- Aktivera SSH i Raspberry Pi Imager
- Sätt hostname (t.ex. `omv-pi`)
- Boota Pi och anslut via SSH

## 2) Basinstallation

Kör i ordning:

```bash
./scripts/00-preflight.sh
sudo reboot
./scripts/10-install-omv.sh
./scripts/20-install-omv-extras.sh
```

## 3) OMV webbgränssnitt

- Gå till `http://<PI-IP>/`
- Byt admin-lösenord
- Verifiera tidszon/NTP

## 4) Diskar och filsystem

- Storage -> Disks: kontrollera att diskar syns
- Storage -> File Systems: skapa (ext4 rekommenderas)
- Montera filsystem
- Skapa shared folders

## 5) Delning och användare

- Users -> skapa användare
- Services -> SMB/CIFS -> aktivera och skapa shares
- (Valfritt) NFS för Linux-klienter

## 6) Hälsa och backup

- Storage -> SMART -> aktivera monitorering
- Scheduled Jobs -> scrub/smart self-tests
- Notifieringar via e-post/SMTP
- Backup av kritisk data till extern disk eller annan nod

## 7) Appar (valfritt)

- Installera Compose-plugin via OMV-Extras
- Kör appar från `apps/compose/`
