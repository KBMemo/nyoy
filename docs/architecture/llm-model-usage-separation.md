# LLMモデル・用途・接続の分離

**ステータス:** Phase 8 用途assignment管理UIへの移行（2026-07-21）

## 1. 目的

LLM設定を次の3責務へ分離する。

1. `ServiceConnection`: llama-server、OpenAI互換API、llama-switchdとの接続・稼働状態
2. `Model`: Runtime Alias、能力、context長などのモデル特性
3. `LlmUsageAssignment`: 用途に対して選択するModel、profile、fallback

実行時の解決順は`usage_key -> assignment -> model -> connection -> API`とする。用途からConnectionを直接選択せず、Connectionのkeyや名前にも用途を持たせない。

sampling値は接続特性ではない。同じModelでも通常Chat、planner、最終回答で異なるため、用途assignmentまたは用途から参照するsampling profileで管理する。

## 2. 用途契約

コード上の正本は`LlmUsageCatalog`とする。

| usage key | 用途 | 必須capability |
| --- | --- | --- |
| `chat.default` | 通常Chatと許可されたtool呼び出し | `text_generation`, `tool_calling` |
| `agent.intent` | Research Graphへの昇格判定 | `text_generation` |
| `agent.planner` | 調査計画 | `text_generation` |
| `agent.evidence_evaluator` | 根拠十分性の評価 | `text_generation` |
| `agent.draft` | 根拠からのドラフト生成 | `text_generation` |
| `agent.final_answer` | 最終回答生成 | `text_generation` |
| `vision.image_understanding` | Chat・ImageUnderstanding Graphの画像理解 | `text_generation`, `vision` |
| `embedding.memo_knowledge` | メモRAGの登録・検索query埋め込み | `embedding` |
| `embedding.prompt_knowledge` | プロンプト知識の登録・検索query埋め込み | `embedding` |
| `image.style_plan` | free flowのstyle plan生成 | `text_generation` |
| `image.direct_prompt` | direct flowのprompt生成 | `text_generation` |
| `utility.chat_history_summary` | 長いChat履歴の要約 | `text_generation` |
| `utility.memo_chunk_compression` | メモchunk圧縮（既定off） | `text_generation` |
| `utility.sd_prompt_translation` | 画像プロンプト翻訳 | `text_generation` |

`tool_calling`は通常Chatの必須能力とする。toolを使わない会話も同じ用途に含め、turnごとにassignmentを切り替えない。structured outputは現行実装にfallbackがあるため、Phase 1では必須capabilityに含めない。

## 3. 旧設定からの移行表

| usage key | 現在の設定元 | 現在のfallback |
| --- | --- | --- |
| `chat.default` | `AppSetting.default_chat_connection_key`、Chatの`Model` | 有効なModel catalogの先頭 |
| `agent.intent` | `AppSetting.agent_graph_intent_model_id` | 通常Chat model |
| `agent.planner` | `AppSetting.research_planner_model_id` | 通常Chat model |
| `agent.evidence_evaluator` | `AppSetting.evidence_evaluator_model_id` | heuristicまたは通常Chat model |
| `agent.draft` | `AppSetting.research_draft_model_id` | 通常Chat model、次にtemplate |
| `agent.final_answer` | `AppSetting.final_answer_model_id` | 通常Chat model |
| `vision.image_understanding` | `ServiceConnection key=vision_llama` | なし（retry後に失敗） |
| `embedding.memo_knowledge` | `ServiceConnection key=embeddings` | なし |
| `embedding.prompt_knowledge` | `ServiceConnection key=embeddings` | なし |
| `image.style_plan` | `default_style_plan_connection_key`、生成recordの`style_plan_connection_key` | `chat.default`のModel |
| `image.direct_prompt` | `style_plan_connection_key` | style plan既定接続 |
| `utility.chat_history_summary` | `LlamaCppClient`既定接続 | `llama_cpp` |
| `utility.memo_chunk_compression` | `LlamaCppClient`既定接続 | `llama_cpp` |
| `utility.sd_prompt_translation` | `LlamaCppClient`既定接続 | `llama_cpp` |

AgentGraphの`intent.hybrid_llm`等のprofile選択とModel選択は別契約である。profileはアルゴリズム実装を選び、usage assignmentはそのprofileがLLMを必要とするときのModelを選ぶ。deterministic profileではassignmentが存在してもLLMを呼ばない。

## 4. Assignment schema

`llm_usage_assignments`は次を保持する。

| column | 意味 |
| --- | --- |
| `usage_key` | `LlmUsageCatalog`の一意な用途key |
| `model_id` | 主Model |
| `fallback_model_id` | 任意の明示fallback Model |
| `llm_sampling_preset_id` | 任意のsampling preset |
| `enabled` | assignmentの利用可否 |

管理画面の「LLM用途」では、用途ごとに主Model、明示fallback Model、sampling preset、有効状態を更新する。Model候補は用途の必須capabilityを満たし、有効なConnectionへ解決できるものに絞る。既存割当が能力不足または接続不能になった場合は候補から黙って除去せず、現在値を残して警告表示する。

profile実装名は保持しない。AgentGraph profileとModel選択を独立させるためである。

Modelの既存`capabilities`と`modalities`は`LlmModelCapabilities`で正規化する。現行互換として`chat`は`text_generation`と`tool_calling`、画像入力modalitiesは`vision`、`embedding(s)`は`embedding`を満たす。assignment保存時に主Modelとfallback Modelの両方を検証する。

`LlmUsageAssignmentSeeds.seed!`は現在のAppSettingと有効なServiceConnectionから、未登録用途だけを移行する。既存assignmentは再seedしても上書きしない。AgentGraphの専用Modelが未設定なら通常Chat Modelを使い、専用Modelがある場合は通常Chat Modelを明示fallbackとして保存する。Vision・Embedding Modelが未登録の場合は、それぞれの接続から能力metadata付きで作成する。

`db:seed`はServiceConnection、Chat Model、sampling presetの後にassignment seedを実行する。productionで通常deploy時にseedを省略している場合は、Phase 3の反映時に`LlmUsageAssignmentSeeds.seed!`を一度明示実行する。

## 5. Runtime resolver

`LlmUsageResolver`は次の順で実行先を決める。

1. 有効なassignmentの主Modelと、そのModelが参照する有効なConnection
2. 主ModelのConnectionが無効なら、明示fallback Modelとその有効なConnection
3. assignmentが未登録または無効なら、consumerが渡す旧設定

通常Chatの既定Modelとsampling preset、AgentGraphのintent・planner・evidence evaluator・draft・final answer、画像理解、メモ・プロンプトRAGのembedding、style plan、direct prompt、Chat履歴要約、メモchunk圧縮、画像prompt翻訳をResolver経由へ移した。

通常Chatではユーザーがチャット作成時に選んだModelを引き続き優先し、`chat.default`は未指定時の既定Modelを決める。画像生成recordが保持する`style_plan_connection_key`も履歴再現性のため優先し、新規recordの既定だけをassignmentから解決する。

旧AppSettingの接続・Model・sampling preset columnからassignmentへの移行は完了した。変更を既存assignmentへ反映するdual-writeを廃止した後、移行安全弁付きmigrationで旧8列も削除した。runtime、管理画面、初回seedはいずれも`LlmUsageAssignment`を正本とする。

## 6. Connection adapter

`ServiceConnection.adapter`は接続プロトコルだけを表す。

| adapter | 責務 |
| --- | --- |
| `llama_cpp` | llama.cppのOpenAI互換model endpoint |
| `openai` | OpenAI model endpoint |
| `llama_switchd` | llama-server control plane |
| `generic` | LLM以外を含む個別API |

従来の`CHAT_BUILTIN_KEYS`、`chat_backends`、`chat_keys`は削除した。Chat catalogはmodel endpointのadapterとModel capabilityから候補を作る。llama-switchd inventoryとreconciliationは`adapter=llama_cpp`を管理対象とし、`gpt_oss`や`vision_llama`等の用途名を列挙しない。

llama-server停止・削除前の用途表示は、有効なassignmentの主Model・fallback ModelからConnectionを逆引きする。assignment未登録時に旧AppSettingへ戻る経路は持たない。

prompt conversion設定は旧UI互換のためmodel endpointに残しているが、最終的なsampling値の所有者はassignmentまたはsampling presetである。

### 6.1 Connection key

llama.cpp model endpointの接続keyは`llama_server_<server identifier>`とする。identifierはllama-switchdのmanaged server IDを優先し、未登録ならRuntime Alias、最後にServiceConnection IDから生成する。これにより`gpt_oss`、`vision_llama`、`embeddings`のような用途名をConnectionの識別子から除く。

移行前のkeyは`ServiceConnection.legacy_key`に保存する。`ServiceConnection.resolve`は現行key、旧keyの順で検索するため、環境変数、旧AppSetting、既存の運用コマンドは移行期間中も利用できる。新規のカスタムllama.cpp接続も保存時にserver指向keyへ正規化し、入力された`llm_*` keyを`legacy_key`として保持する。

移行migrationはConnectionのkey変更と同時に、AppSettingの既定接続、画像生成履歴のstyle plan接続、Model metadataの`connection_key`を更新する。用途assignmentはModelを参照しているため更新不要である。`legacy_key`は旧運用コマンドとの互換識別子として残し、利用状況を確認してから別途削除を判断する。

### 6.2 Runtime connection source

llama.cpp model endpointの実行時接続情報はServiceConnectionだけを正本とする。`LLAMA_CPP_URL`、`GPT_OSS_LLAMA_CPP_URL`、`VISION_LLAMA_CPP_URL`、`EMBEDDINGS_URL`と対応するModel環境変数は、初回の`ServiceConnectionSeeds`用入力としてのみ利用する。接続レコードが存在しない、無効、または値が空の場合も、実行時に環境変数へfallbackしない。

これにより、管理画面で無効化した接続が環境変数によって再び利用される経路をなくす。LLM以外の外部サービスは本分離の対象外であり、既存の環境変数fallbackを維持する。用途選択に使っていた`DEFAULT_CHAT_CONNECTION_KEY`と`STYLE_PLAN_CONNECTION_KEY`も廃止し、初回seedはModel catalogからassignmentを作る。

## 7. 不変条件

- `ServiceConnection`は用途keyを保持しない
- 用途選択UIはConnectionではなくModelを表示する
- Modelは必須capabilityをすべて満たす用途にだけ選択できる
- Modelから有効なConnectionを解決できない場合、そのassignmentは利用不可とする
- Runtime AliasやURL変更で用途assignmentを変更しない
- lifecycle操作前の使用中判定は、Connectionへの直接参照ではなくassignmentから逆引きする
- fallbackは暗黙のURL fallbackではなくassignment上で明示する

## 8. 移行順序

1. 用途keyと能力要件を定義する（本Phase）
2. `LlmUsageAssignment`を追加する
3. 既存AppSetting・AgentGraph model設定からassignmentをseedする
4. Chat、AgentGraph、Vision、Embedding、画像prompt、補助処理をassignment解決へ移す
5. `ServiceConnection`の用途依存scope・validation・UIを除去する
6. 用途名を含む接続keyをserver指向keyへ移行する（完了）
7. 用途別URL環境変数fallbackを非推奨化し、移行期間後に削除する（完了）
8. 用途assignment管理UIへ移行し、旧AppSetting dual-writeを削除する（完了）
9. 用途選択環境変数を廃止し、初回seedをModel基準へ統一する（完了）
10. runtimeの旧接続キーfallbackを廃止し、用途assignmentを必須化する（完了）
11. 旧AppSettingのLLM設定8列を安全弁付きmigrationで削除する（完了）

## 9. Legacy key監査

`bin/rails service_connections:legacy_key_audit`は、各`ServiceConnection.legacy_key`について生成履歴とModel metadataに旧keyが残っていないかJSONで報告する。`STRICT=1`を付けると旧参照が1件でもあれば終了statusを失敗にする。

2026-07-21のdevelopment DB監査では、Model metadataと生成履歴はcanonical keyへ移行済みだった。runtimeのassignment未登録時fallbackも廃止済みである。`legacy_key`自体は初期seed定義と外部運用コマンドの移行期間に使うため、現時点では削除しない。削除条件はDB監査がclearであり、外部クライアントがcanonical keyまたはusage keyからの動的解決へ移行していることである。

`LlmUsageResolver.llama_client_for`、`EmbeddingClient`、`VisionChatService`は有効な用途assignmentを解決できない場合に明示エラーを返す。`LlamaCppClient`は既定接続を持たず、解決済み`base_url`を必須引数として受け取る。これによりassignmentの設定不備が別モデルへの暗黙接続として隠れない。

各Phaseは旧経路との互換期間を設ける。全consumerの切替前に旧columnや環境変数を削除しない。
