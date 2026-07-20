# AgentGraph Core 分離再評価

評価日: 2026-07-20

## 結論

`agent_graph-core` は当面Nyoy repository内のprivate path gemとして維持する。別repository化や公開gem化はまだ行わない。

Coreの技術的な分離条件は満たしているが、独立配布を必要とする第二利用者やrelease要件がない。現在分離すると、repository、version、互換性、security updateを管理する負担だけが先に発生する。

## 確認結果

| 項目 | 状態 |
| --- | --- |
| Rails / ActiveRecord / ChatTools依存 | Core package内に参照なし |
| runtime dependency | なし |
| standalone test | 3 tests / 17 assertions、成功 |
| gem build | `agent_graph-core-0.1.0.gem`、成功 |
| Nyoy接続 | Bundler path dependency + 互換alias |
| workflow追加 | Registry登録形式を固定、DiagnosticGraphで検証済み |
| role差し替え | 全標準roleで接続済み。vision / memo_writerも実Graph overrideを確認 |
| persistence / retry | Coreはcontext protocolだけを要求 |

Nodeに残る`ChatTools`、Active Storage、葛籠、Chatへの依存は、具体workflowを実行するNyoy adapterの責務であり、Coreへ移さない。

## 現時点の公開blocker

- 第二利用者と要求APIが存在しない
- 対応RubyがNyoy採用中の4.0.3だけ
- licenseが`Nonstandard`で再配布条件を確定していない
- homepage、issue tracker、security policyがNyoy repository前提
- changelog、release tag、互換性確認の運用がない
- `0.1.x` public APIを外部利用で検証していない

これらはbuild不能を意味しない。外部利用者へ保守を約束する段階ではない、という配布上の判断である。

## 再評価trigger

次のいずれかが発生した時点で再評価する。

1. Nyoy以外のapplicationがCore Runnerを実際に利用する
2. Nyoyとは独立したrelease cadenceが必要になる
3. 外部contributorへCoreだけのissue / PR境界が必要になる
4. Ruby version matrixを定義して継続CIできる
5. licenseと公開先を確定できる

単なるコード量増加や「gemだから」という理由だけではrepositoryを分けない。

## 分離時の手順

1. public APIと互換性方針を確定する
2. license、homepage、source、changelogをgemspecへ反映する
3. 対応Ruby matrixでstandalone CIを通す
4. package履歴を保持して新repositoryへ抽出する
5. `0.x` tagを発行し、NyoyのGemfileを`git:` + tagへ変更する
6. NyoyのCore test、Rails test、Zeitwerk、gem buildを通す
7. 第二利用者でも同じtagを使ってintegration testを通す

`1.0.0` は第二利用者でContextProtocolと遷移semanticsが安定してから判断する。
