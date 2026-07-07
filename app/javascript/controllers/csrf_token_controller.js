import { Controller } from "@hotwired/stimulus"

// Forms delivered via Turbo Stream broadcasts are rendered server-side without
// the user's session, so their embedded authenticity_token cannot be verified
// and a submit raises ActionController::InvalidAuthenticityToken. Re-sync the
// hidden token from the page's <meta name="csrf-token"> (valid for this
// session) whenever such a form connects.
export default class extends Controller {
  connect() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    if (!token) return

    const field = this.element.querySelector('input[name="authenticity_token"]')
    if (field) field.value = token
  }
}
