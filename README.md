# OMV Pi NAS (Raspberry Pi 5)

Detta repo innehåller återanvändbara script och app-definitioner för att sätta upp en Raspberry Pi 5 som NAS med OpenMediaVault (OMV).

## Målbild

- Bas-OS: Raspberry Pi OS Lite 64-bit (Bookworm) eller Debian 12
- NAS-lager: OpenMediaVault 7
- Tillägg: OMV-Extras (Compose, extra plugins)
- Appar: Docker Compose-filer i `apps/`

## Snabbstart

Kör på en nyinstallerad Pi (SSH inloggad som användare med sudo):

```bash
git clone https://github.com/Y0daman/omv_pinas.git
cd omv_pinas
chmod +x scripts/*.sh

./scripts/00-preflight.sh
./scripts/10-install-omv.sh
./scripts/20-install-omv-extras.sh
```

Efter installation:

1. Logga in i OMV webbgränssnitt: `http://<PI-IP>/`
2. Sätt statisk IP (rekommenderas)
3. Lägg till disk(ar), skapa filsystem, montera
4. Skapa delningar (SMB/NFS) och användare
5. Aktivera SMART, scrub och notifieringar

## Repo-struktur

- `scripts/` - automatisering för installation och grundkonfig
- `apps/` - Compose-appar som kan köras via OMV Compose-plugin eller Docker CLI
- `docs/` - manualer/checklistor

## Viktiga råd

- Kör detta på ren installation för att undvika konflikter.
- Anslut USB/SATA-diskar med egen strömförsörjning.
- Använd helst UPS om du kör RAID/mer kritiska data.
- Backup först, experimentera sedan.

## Nästa steg

Se `docs/setup-checklist.md` för hela ordningen från SD-flash till färdig NAS.
