# LLMモデル・用途・接続の分離

**ステータス:** Phase 5 ServiceConnection用途依存の除去（2026-07-21）

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

## 3. 現行設定からの移行表

| usage key | 現在の設定元 | 現在のfallback |
| --- | --- | --- |
| `chat.default` | `AppSetting.default_chat_connection_key`、Chatの`Model` | `DEFAULT_CHAT_CONNECTION_KEY` |
| `agent.intent` | `AppSetting.agent_graph_intent_model_id` | 通常Chat model |
| `agent.planner` | `AppSetting.research_planner_model_id` | 通常Chat model |
| `agent.evidence_evaluator` | `AppSetting.evidence_evaluator_model_id` | heuristicまたは通常Chat model |
| `agent.draft` | `AppSetting.research_draft_model_id` | 通常Chat model、次にtemplate |
| `agent.final_answer` | `AppSetting.final_answer_model_id` | 通常Chat model |
| `vision.image_understanding` | `ServiceConnection key=vision_llama` | なし（retry後に失敗） |
| `embedding.memo_knowledge` | `ServiceConnection key=embeddings` | なし |
| `embedding.prompt_knowledge` | `ServiceConnection key=embeddings` | なし |
| `image.style_plan` | `default_style_plan_connection_key`、生成recordの`style_plan_connection_key` | `STYLE_PLAN_CONNECTION_KEY` |
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

旧AppSetting画面との互換期間中は、関連する接続・Model・sampling preset columnの変更を既存assignmentへdual-writeする。assignment管理UIへの移行完了後にこの同期を削除する。

## 6. Connection adapter

`ServiceConnection.adapter`は接続プロトコルだけを表す。

| adapter | 責務 |
| --- | --- |
| `llama_cpp` | llama.cppのOpenAI互換model endpoint |
| `openai` | OpenAI model endpoint |
| `llama_switchd` | llama-server control plane |
| `generic` | LLM以外を含む個別API |

従来の`CHAT_BUILTIN_KEYS`、`chat_backends`、`chat_keys`は削除した。Chat catalogはmodel endpointのadapterとModel capabilityから候補を作る。llama-switchd inventoryとreconciliationは`adapter=llama_cpp`を管理対象とし、`gpt_oss`や`vision_llama`等の用途名を列挙しない。

llama-server停止・削除前の用途表示は、有効なassignmentの主Model・fallback ModelからConnectionを逆引きする。assignmentがまだ1件もない移行前DBだけ、旧AppSetting判定へfallbackする。

prompt conversion設定は旧UI互換のためmodel endpointに残しているが、最終的なsampling値の所有者はassignmentまたはsampling presetである。接続keyのserver指向移行と旧UI削除は後続Phaseで行う。

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
6. 用途名を含む接続keyをserver指向keyへ移行する
7. 用途別URL環境変数fallbackを非推奨化し、移行期間後に削除する

各Phaseは旧経路との互換期間を設ける。全consumerの切替前に旧columnや環境変数を削除しない。
