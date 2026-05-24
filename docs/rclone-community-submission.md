# rclone community submission

This project can be submitted to the rclone ecosystem in two friendly places:

- rclone Wiki: <https://github.com/rclone/rclone/wiki/Third-Party-Integrations-with-rclone>
- rclone Forum: <https://forum.rclone.org/>

## Wiki entry

Suggested location: after `rclone_jobber` on the third-party integrations page.

```markdown
## GDrive Tiger Backup

[GDrive Tiger Backup](https://github.com/AlexanderSmyslowski/gdrive-tiger-backup) is an open-source macOS helper for creating local Google Drive backups with rclone. It supports external disks via launchd `StartOnMount`, NAS/network destinations, scheduled backups, Google Docs/Sheets/Slides export, and a small multilingual Mac OS X Tiger-style setup/status UI. It uses `rclone copy`, so it does not delete or modify files in Google Drive.
```

## Forum post

Suggested category: `Community` or `Off-topic`, depending on the current rclone Forum structure.

Suggested title:

```text
GDrive Tiger Backup: macOS launchd + NAS/external disk Google Drive backup helper
```

Suggested body:

```markdown
Hi rclone community,

I built a small open-source macOS helper around rclone for people who want a local Google Drive backup without turning it into a destructive sync.

Project:
https://github.com/AlexanderSmyslowski/gdrive-tiger-backup

What it does:

- backs up My Drive, Shared Drives, and "Shared with me"
- exports Google Docs, Sheets, and Slides as docx/xlsx/pptx
- uses `rclone copy`, so it does not delete or modify files in Google Drive
- supports external disks through a launchd `StartOnMount` agent
- supports NAS/network destinations and scheduled backups
- includes a small multilingual Mac OS X Tiger-style setup/status app for macOS

It is not affiliated with rclone; it is just a helper that uses rclone as the transfer engine. I thought it might be useful for macOS users looking for a simple external-disk or NAS Google Drive backup workflow.
```
