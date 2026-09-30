# Security

## Reporting a problem

Please do not open a public issue for a security problem. Report it in private: open the repository's
**Security** tab on GitHub and choose **Report a vulnerability**. You get an answer there, and the report stays
private until a fix is released.

Useful in a report: the addon version (`/wfj version`), the client build, what happens, and the steps that make
it happen.

## What counts

- The addon: anything that lets game text, another addon or another player make the addon run code, break the
  client, or write something into the saved settings that the player did not choose.
- The report and the collector file: anything that puts a character name, a realm, an account name or another
  player's text into a file the player is asked to post.
- The pipeline and the workflows: anything in an issue, a pull request or a data file that makes the tools run
  code, write outside the repository, or publish a release.

A wrong translation is not a security problem: use the
[translation report](https://github.com/zyaga/wow-forever-japanese/issues/new?template=translation-report.yml).

## Supported versions

Fixes go into the next release. Only the latest release is supported.

## 日本語

セキュリティ上の問題は、公開の Issue ではなく非公開で報告してください。GitHub のリポジトリの **Security** タブを開き、
**Report a vulnerability** を選びます。返信はそこで行い、修正版が公開されるまで報告は非公開のままです。

報告には、アドオンのバージョン（`/wfj version`）、クライアントのビルド、起きたこと、再現手順を書いてください。

翻訳の誤りはセキュリティの問題ではありません。
[翻訳の報告フォーム](https://github.com/zyaga/wow-forever-japanese/issues/new?template=translation-report.yml)をご利用ください。

修正は次のリリースに入ります。サポート対象は最新のリリースのみです。
