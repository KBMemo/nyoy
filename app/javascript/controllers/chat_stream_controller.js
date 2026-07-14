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
    this.subscription = consumer.subscriptions.create(
      { channel: "ChatChannel", chat_id: this.chatIdValue },
      { received: (event) => this.received(event) }
    )
  }

  disconnect() {
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
      case "research_progress":
        this.replaceResearchProgress(event)
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
      this.element.append(next)
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
    const mount = document.getElementById("research_approval")
    if (!mount) return

    mount.innerHTML = event.html || ""
  }

  replaceResearchProgress(event) {
    const mount = document.getElementById("research_progress")
    if (!mount) return

    mount.innerHTML = event.html || ""
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
    this.element.append(message)
    return message
  }
}
