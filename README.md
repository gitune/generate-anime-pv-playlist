# これはなに？

YouTubeに上がったアニメの公式PVをプレイリストに自動的にまとめるためのシェルスクリプトです。

# 使い方

## 事前準備

このシェルスクリプトを動かすにはいろいろと準備が必要です。

#### 1. 管理用のYouTubeアカウントを用意する

スクリプトを動かすためのYouTubeアカウントを用意します。またYouTubeチャンネルも準備し、アカウントの設定からそのアカウントの登録チャンネルを公開状態に変更しておきます。

#### 2. PVを検索したい公式チャンネルを上記アカウントにひたすら登録する

海賊版等が混入することを防ぐため、あらかじめ登録された公式チャンネルに上がったPVのみを対象としています。

#### 3. PVをまとめるプレイリストを作成し、そのIDとそのリストで対象とする作品のタイトルをまとめた `txt` ファイルを用意する

その `txt` ファイルには、

* 1行目にプレイリストのIDを記入し、
* 2行目以降に対象作品の名前を並べます。

なおプレイリストにPVはこの `txt` ファイルに書かれた順番＋時刻順で格納されていきますので順番は重要です。以下サンプル。

```
PLQlUOJwsG0MwwPuq7DyJEfwjn3irnx9BM
アイドルマスター シンデレラガールズ U149
青のオーケストラ
異世界召喚は二度目です
異世界でチート能力を手にした俺は、現実世界をも無双する ～レベルアップは人生を変えた～
異世界はスマートフォンとともに。
ウマ娘 プリティーダービー Road to the Top
ULTRAMAN FINALシーズン
EDENS ZERO
王様ランキング 勇気の宝箱
```

あ、一つ大事なことを書き忘れましたが上記 `txt` ファイルのファイル名は `playlist_[任意].txt` とする必要があります。また更新したいプレイリストが複数ある場合は上記 `txt` ファイルをスクリプトと同じディレクトリに複数用意してください。

#### 4. YouTube Data APIを利用できるAPI KEYとOAuth credentialを用意する

これが一番めんどくさいかもしれませんが💦、YouTube Data APIを利用できるAPI KEYとOAuth credential(OAuth client ID, client secret, refresh token)を用意する必要があります。ただググると先輩達がたくさん資料を残してくれていますので、そういった情報を活用しましょう。僕は下記ページなどを参考にしました。本当にどうもありがとうございます。

* [YouTube Data API v3 を使って YouTube 動画を検索する](https://qiita.com/koki_develop/items/4cd7de3898dae2c33f20)
* [バッチ処理だけどYoutube Auth認証が必要だったので楽に何とかする](https://qiita.com/abeyuya/items/1739e15e73e4565186bb)

#### 5. 必要な情報を環境変数にセットする

ここまででそろった必要な情報を環境変数にセットしておきます。cronで動かしたりする場合も忘れずにセットするようにしましょう。

| environment variables | 説明 |
| ------------- | ------------ |
| YOUTUBE_CHANNEL_ID | 1.で作成したYouTubeチャンネルのID |
| YOUTUBE_API_KEY | YouTube Data APIを利用できるAPI KEY |
| YOUTUBE_CLIENT_ID | YouTube Data APIを利用できるOAuth client ID |
| YOUTUBE_CLIENT_SECRET | YouTube Data APIを利用できるOAuth client secret |
| YOUTUBE_REFRESH_TOKEN | YouTube Data APIを利用できるOAuth refresh token |

## 実行

後はスクリプトを動かすだけです。あまり標準的でないcommandは使っていないつもりですが、 `jq` や `curl` などは入っていなければ入れる必要があるかもしれません。

# 注意点

手元の環境では、このスクリプトを動かすと400弱単位くらいYouTube Data APIのquataを利用するようですので、無料枠ですと1日に動かせる回数は20回程度が上限のようです。ご注意あれ。
