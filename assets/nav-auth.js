// ── NAVIGATOR ALGO · NAV AUTH PILL ──
// Renders the "Sign in" link OR a signed-in user menu in the nav bar of every
// page. Expects a slot element with id="nav-auth-slot" inside the nav <ul>.
//
// Imported by: index.html, signal-copier.html, receiver-download.html,
//              dashboard.html, signin.html, profile.html

import { watchAuth, signOutUser, touchUserProfile } from "./app.js";

const slot = document.getElementById("nav-auth-slot");
if (!slot) {
  console.warn("[Navigator Algo] nav-auth.js loaded but #nav-auth-slot not found on page.");
}

function initial(name) {
  return (name || "?").trim().charAt(0).toUpperCase() || "?";
}

function friendlyName(user) {
  if (user.displayName) return user.displayName;
  if (user.email) return user.email.split("@")[0];
  return "Account";
}

function renderSignedOut() {
  if (!slot) return;
  slot.innerHTML =
    `<a href="signin.html" class="nav-btn-ghost">Sign in</a>`;
}

function renderSignedIn(user) {
  if (!slot) return;
  const name = friendlyName(user);
  const photo = user.photoURL
    ? `<img class="nav-user-avatar" src="${user.photoURL}" alt="" referrerpolicy="no-referrer">`
    : `<span class="nav-user-avatar nav-user-avatar-fallback">${initial(name)}</span>`;

  slot.innerHTML = `
    <div class="nav-user" id="navUser">
      <button type="button" class="nav-user-btn" id="navUserBtn" aria-haspopup="true" aria-expanded="false">
        ${photo}
        <span class="nav-user-name">${escapeHtml(name)}</span>
        <svg class="nav-user-caret" width="10" height="10" viewBox="0 0 10 10" aria-hidden="true">
          <path d="M1.5 3.5L5 7l3.5-3.5" stroke="currentColor" stroke-width="1.5" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
      </button>
      <div class="nav-user-menu" id="navUserMenu" role="menu">
        <div class="nav-user-meta">
          <div class="nav-user-meta-name">${escapeHtml(name)}</div>
          ${user.email ? `<div class="nav-user-meta-email">${escapeHtml(user.email)}</div>` : ""}
        </div>
        <a href="dashboard.html" role="menuitem">Dashboard</a>
        <a href="profile.html"   role="menuitem">Profile</a>
        <button type="button" id="navSignOutBtn" role="menuitem">Sign out</button>
      </div>
    </div>
  `;

  const btn  = slot.querySelector("#navUserBtn");
  const menu = slot.querySelector("#navUserMenu");

  function close() {
    menu.classList.remove("open");
    btn.setAttribute("aria-expanded", "false");
    document.removeEventListener("click", onDocClick, true);
    document.removeEventListener("keydown", onKey, true);
  }
  function open() {
    menu.classList.add("open");
    btn.setAttribute("aria-expanded", "true");
    document.addEventListener("click", onDocClick, true);
    document.addEventListener("keydown", onKey, true);
  }
  function onDocClick(e) {
    if (!slot.contains(e.target)) close();
  }
  function onKey(e) {
    if (e.key === "Escape") close();
  }

  btn.addEventListener("click", (e) => {
    e.stopPropagation();
    if (menu.classList.contains("open")) close();
    else open();
  });

  slot.querySelector("#navSignOutBtn").addEventListener("click", async () => {
    try {
      await signOutUser();
    } finally {
      window.location.replace("index.html");
    }
  });
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

watchAuth(
  (user) => {
    renderSignedIn(user);
    // Fire-and-forget refresh of /users/{uid}; errors are non-fatal for nav display.
    touchUserProfile(user).catch((e) => {
      console.warn("[Navigator Algo] touchUserProfile failed:", e?.code || e?.message || e);
    });
  },
  () => {
    renderSignedOut();
  }
);
