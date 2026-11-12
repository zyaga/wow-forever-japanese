# Release media

The pictures and the clip a release's Discord post carries ([Release](../operations/release.md), [ADR-072](../adr/072-the-release-announces-itself-in-discord.md)).

`next/` holds what the next post carries. `en.md` and `ja.md` are the post's text: a short summary of the release in each language, four to six lines with the most important first, written once before the release, which refuses to start without them. The full changelog is a link in the post. A feature worth showing off also adds its CurseForge gallery card (jpg, png, webp or gif) and a short clip when it has one (mp4, webm or mov); most changes add no picture. Each file under 20 MiB, at most ten in all. The post shows the clip and the pictures as tiles at the top, then the English card and the Japanese card under them. A release with no pictures posts its cards alone.

The release run renames `next/` to the version it cuts, in the same commit as the changelog, so the folder for each release stays here under its number. The "Discord preview" workflow posts what the next release would look like, with the files in `next/`, to the test channel.

Between releases this folder holds this file, `next/` while media waits, and one folder per released version. Nothing in this folder ships in the addon.
