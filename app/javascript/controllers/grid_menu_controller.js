import { Controller } from "@hotwired/stimulus";

// Connects to data-controller="grid-menu"
export default class extends Controller {
  static targets = ["icon", "menu"];

  connect() {
    // Close menu when clicking outside
    this.boundCloseOnClickOutside = this.closeOnClickOutside.bind(this);
    document.addEventListener("click", this.boundCloseOnClickOutside);
  }

  disconnect() {
    document.removeEventListener("click", this.boundCloseOnClickOutside);
  }

  toggle(event) {
    event.stopPropagation();
    this.menuTarget.classList.toggle("show");
  }

  closeOnClickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.menuTarget.classList.remove("show");
    }
  }
}
