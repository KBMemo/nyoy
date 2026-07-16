import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const consumer = createConsumer()

export default class extends Controller {
  static values = {
    chatId: Number
  }

  connect() {
    this.finalizedSeqByMessageId = new Map()
    this.latestSeqByMessageTarget = new Map()
    this.progressClock = null
    this.subscription = consumer.subscriptions.create(
      { channel: "ChatChannel", chat_id: this.chatIdValue },
      { received: (event) => this.received(event) }
    )
  }

  disconnect() {
    this.clearProgressClock()
    this.subscription?.unsubscribe()
  }

  received(event) {
    switch (event.type) {
      case "assistant_content":
        this.updateAssistantContent(event)
        break
      case "assistant_thinking":
        this.updateAssistantThinking(event)
        break
      case "assistant_finalized":
      case "message_upsert":
        this.upsertMessage(event)
        break
      case "message_removed":
        this.removeMessage(event)
        break
      case "form_updated":
        this.replaceForm(event)
        break
      case "approval_panel":
        this.replaceApprovalPanel(event)
        break
      case "agent_run_progress":
        this.replaceAgentRunProgress(event)
        break
      case "agent_run_progress_thinking":
        this.updateAgentRunProgressThinking(event)
        break
      case "agent_run_progress_prompts":
        this.updateAgentRunProgressPrompts(event)
        break
    }
  }

  updateAssistantContent(event) {
    if (!this.acceptStreamingSequence(event, "content")) return

    const message = this.ensureAssistantMessage(event.message_id)
    const content = message.querySelector(`#message_${event.message_id}_content`)
    content.classList.add("nyoy-chat-streaming-raw")
    content.textContent = event.text || ""
  }

  updateAssistantThinking(event) {
    if (!this.acceptStreamingSequence(event, "thinking")) return

    const message = this.ensureAssistantMessage(event.message_id)
    let section = message.querySelector(`#message_${event.message_id}_thinking_section`)
    section.classList.remove("hidden")
    section.innerHTML = ""

    const details = document.createElement("details")
    details.className = "nyoy-chat-message-thinking-details"
    details.open = true

    const summary = document.createElement("summary")
    summary.className = "nyoy-chat-message-thinking-summary"
    summary.textContent = "思考"

    const pre = document.createElement("pre")
    pre.id = `message_${event.message_id}_thinking`
    pre.className = "nyoy-chat-message-thinking"
    pre.dataset.controller = "thinking-auto-scroll"
    pre.textContent = event.text || ""

    details.append(summary, pre)
    section.append(details)
  }

  upsertMessage(event) {
    if (!this.acceptFinalizedSequence(event)) return
    if (!event.html) return

    const template = document.createElement("template")
    template.innerHTML = event.html.trim()
    const next = template.content.firstElementChild
    if (!next) return

    const current = document.getElementById(next.id)
    if (current) {
      current.replaceWith(next)
    } else {
      this.insertMessageNode(next)
    }
    this.pinAgentRunProgress()
    this.revealImportantMessage(next)
    // Agent run approve publishes a full assistant message without streaming —
    // bring it into view so the draft panel doesn't feel like it vanished.
    if (next.classList?.contains("nyoy-chat-message-assistant")) {
      next.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }
  }

  revealImportantMessage(node) {
    if (!node) return
    const important =
      node.classList?.contains("nyoy-chat-message-error") ||
      node.querySelector?.(".nyoy-chat-message-truncated-note")
    if (important) {
      node.scrollIntoView({ behavior: "smooth", block: "nearest" })
    }
  }

  removeMessage(event) {
    document.getElementById(`message_${event.message_id}`)?.remove()
    this.finalizedSeqByMessageId.delete(String(event.message_id))
  }

  replaceForm(event) {
    const current = document.getElementById("new_message")
    if (!current || !event.html) return

    const template = document.createElement("template")
    template.innerHTML = event.html.trim()
    const next = template.content.firstElementChild
    if (next) current.replaceWith(next)
  }

  replaceApprovalPanel(event) {
    const mount = document.getElementById("agent_run_approval")
    if (!mount) return

    mount.innerHTML = event.html || ""
  }

  replaceAgentRunProgress(event) {
    const mount = this.ensureAgentRunProgressMount()
    if (!mount) return

    this.clearProgressClock()
    mount.innerHTML = event.html || ""
    this.pinAgentRunProgress()

    if (!event.html) return

    const panel = mount.querySelector("#agent_run_progress_panel")
    const nodeStartedAt = event.node_started_at || panel?.dataset?.nodeStartedAt
    const runStartedAt = event.run_started_at || panel?.dataset?.runStartedAt
    this.startProgressClock(nodeStartedAt, runStartedAt)
    panel?.scrollIntoView({ behavior: "smooth", block: "nearest" })
  }

  updateAgentRunProgressThinking(event) {
    const text = event.text || ""
    if (!text) return

    const mount = this.ensureAgentRunProgressMount()
    const panel = mount?.querySelector("#agent_run_progress_panel")
    if (!panel) return

    let section = panel.querySelector("#agent_run_progress_thinking_section")
    if (!section) {
      section = document.createElement("div")
      section.id = "agent_run_progress_thinking_section"
      section.className = "nyoy-agent-run-progress-thinking-section"
      panel.querySelector(".nyoy-agent-run-progress-body")?.append(section)
    }

    section.classList.remove("hidden")

    let pre = section.querySelector("#agent_run_progress_thinking")
    if (!pre) {
      const details = document.createElement("details")
      details.className = "nyoy-chat-message-thinking-details"
      details.open = true

      const summary = document.createElement("summary")
      summary.className = "nyoy-chat-message-thinking-summary"
      summary.textContent = "思考"

      pre = document.createElement("pre")
      pre.id = "agent_run_progress_thinking"
      pre.className = "nyoy-chat-message-thinking nyoy-agent-run-progress-thinking"
      pre.dataset.controller = "thinking-auto-scroll"

      details.append(summary, pre)
      section.replaceChildren(details)
    }

    pre.textContent = text
  }

  updateAgentRunProgressPrompts(event) {
    const systemText = event.system || ""
    const userText = event.user || ""
    if (!systemText && !userText) return

    const mount = this.ensureAgentRunProgressMount()
    const panel = mount?.querySelector("#agent_run_progress_panel")
    if (!panel) return

    let section = panel.querySelector("#agent_run_progress_prompts_section")
    if (!section) {
      section = document.createElement("div")
      section.id = "agent_run_progress_prompts_section"
      section.className = "nyoy-agent-run-progress-prompts-section"
      const body = panel.querySelector(".nyoy-agent-run-progress-body")
      const thinking = panel.querySelector("#agent_run_progress_thinking_section")
      if (thinking) {
        thinking.before(section)
      } else {
        body?.append(section)
      }
    }

    section.classList.remove("hidden")

    if (systemText) {
      let systemPre = section.querySelector("#agent_run_progress_system_prompt")
      if (!systemPre) {
        const details = document.createElement("details")
        details.className = "nyoy-chat-message-thinking-details"
        details.open = true

        const summary = document.createElement("summary")
        summary.className = "nyoy-chat-message-thinking-summary"
        summary.textContent = "システムプロンプト"

        systemPre = document.createElement("pre")
        systemPre.id = "agent_run_progress_system_prompt"
        systemPre.className = "nyoy-chat-message-thinking nyoy-agent-run-progress-prompt"

        details.append(summary, systemPre)
        section.prepend(details)
      }
      systemPre.textContent = systemText
      systemPre.closest("details")?.classList.remove("hidden")
    }

    if (userText) {
      let userDetails = section.querySelector(".nyoy-agent-run-progress-user-prompt-details")
      let userPre = section.querySelector("#agent_run_progress_user_prompt")
      if (!userPre) {
        userDetails = document.createElement("details")
        userDetails.className = "nyoy-chat-message-thinking-details nyoy-agent-run-progress-user-prompt-details"

        const summary = document.createElement("summary")
        summary.className = "nyoy-chat-message-thinking-summary"
        summary.textContent = "ユーザープロンプト"

        userPre = document.createElement("pre")
        userPre.id = "agent_run_progress_user_prompt"
        userPre.className = "nyoy-chat-message-thinking nyoy-agent-run-progress-prompt"

        userDetails.append(summary, userPre)
        section.append(userDetails)
      }
      userPre.textContent = userText
      userDetails?.classList.remove("hidden")
    }
  }

  ensureAgentRunProgressMount() {
    let mount = document.getElementById("agent_run_progress")
    if (mount) return mount

    mount = document.createElement("div")
    mount.id = "agent_run_progress"
    this.element.append(mount)
    return mount
  }

  pinAgentRunProgress() {
    const mount = document.getElementById("agent_run_progress")
    if (!mount || !this.element.contains(mount)) return

    this.element.append(mount)
  }

  insertMessageNode(node) {
    const mount = document.getElementById("agent_run_progress")
    if (mount && this.element.contains(mount)) {
      mount.before(node)
    } else {
      this.element.append(node)
    }
  }

  startProgressClock(nodeStartedAt, runStartedAt) {
    this.clearProgressClock()
    const nodeAt = Date.parse(nodeStartedAt || "")
    const runAt = Date.parse(runStartedAt || "")
    if (!Number.isFinite(nodeAt) && !Number.isFinite(runAt)) return

    const tick = () => {
      const nodeEl = this.element.querySelector("[data-agent-run-progress-elapsed]")
      const runEl = this.element.querySelector("[data-agent-run-progress-run-elapsed]")
      if (!nodeEl && !runEl) {
        this.clearProgressClock()
        return
      }

      const now = Date.now()
      if (nodeEl && Number.isFinite(nodeAt)) {
        nodeEl.textContent = this.formatElapsed(now - nodeAt)
      }
      if (runEl && Number.isFinite(runAt)) {
        runEl.textContent = `合計 ${this.formatElapsed(now - runAt)}`
      }
    }

    tick()
    this.progressClock = window.setInterval(tick, 1000)
  }

  clearProgressClock() {
    if (this.progressClock) {
      window.clearInterval(this.progressClock)
      this.progressClock = null
    }
  }

  formatElapsed(ms) {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000))
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    if (minutes <= 0) return `${seconds}秒`
    return `${minutes}分${seconds}秒`
  }

  acceptStreamingSequence(event, target) {
    if (!event.message_id || event.seq === undefined || event.seq === null) return true

    const key = String(event.message_id)
    const seq = Number(event.seq)
    const finalizedSeq = this.finalizedSeqByMessageId.get(key)
    if (finalizedSeq !== undefined && seq <= finalizedSeq) return false

    const targetKey = `${key}:${target}`
    const previous = this.latestSeqByMessageTarget.get(targetKey)
    if (previous !== undefined && seq < previous) return false

    this.latestSeqByMessageTarget.set(targetKey, seq)
    return true
  }

  acceptFinalizedSequence(event) {
    if (event.type !== "assistant_finalized") return true
    if (!event.message_id || event.seq === undefined || event.seq === null) return true

    const key = String(event.message_id)
    const seq = Number(event.seq)
    const previous = this.finalizedSeqByMessageId.get(key)
    if (previous !== undefined && seq < previous) return false

    this.finalizedSeqByMessageId.set(key, seq)
    return true
  }

  ensureAssistantMessage(messageId) {
    const existing = document.getElementById(`message_${messageId}`)
    if (existing) return existing

    const message = document.createElement("div")
    message.id = `message_${messageId}`
    message.className = "nyoy-chat-message nyoy-chat-message-assistant"

    const header = document.createElement("div")
    header.className = "nyoy-chat-message-header"

    const role = document.createElement("div")
    role.className = "nyoy-chat-message-role"
    role.textContent = "アシスタント"
    header.append(role)

    const thinking = document.createElement("div")
    thinking.id = `message_${messageId}_thinking_section`
    thinking.className = "nyoy-chat-message-thinking-section hidden"

    const content = document.createElement("div")
    content.id = `message_${messageId}_content`
    content.className = "nyoy-chat-message-content nyoy-chat-markdown nyoy-chat-streaming-raw"

    const meta = document.createElement("div")
    meta.className = "nyoy-chat-message-meta"

    message.append(header, thinking, content, meta)
    this.insertMessageNode(message)
    this.pinAgentRunProgress()
    return message
  }
}
