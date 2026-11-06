# Release media

The pictures and the clip a release's Discord post carries ([Release](../operations/release.md), [ADR-072](../adr/072-the-release-announces-itself-in-discord.md)).

Put the files for the next release in `next/`: the feature cards made for the CurseForge gallery (jpg, png, webp or gif, at most four) and a short clip (mp4, webm or mov), each under 20 MiB, at most ten in all, plus `ja.md`, the Japanese text of the post. The post shows the first picture in full under the English card, the rest as a small gallery, the Japanese card under that, and the clip in its own player under the cards. A release with no `next/` folder posts its English card alone.

The release run renames `next/` to the version it cuts, in the same commit as the changelog, so the folder for each release stays here under its number. The "Discord preview" workflow posts what the next release would look like, with the files in `next/`, to the test channel.

Between releases this folder holds this file, `next/` while media waits, and one folder per released version. Nothing in this folder ships in the addon.
