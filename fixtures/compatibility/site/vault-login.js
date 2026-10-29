"use strict";

const form = document.getElementById("vault-login");
const username = document.getElementById("username");
const password = document.getElementById("password");
const result = document.getElementById("vault-result");

form.addEventListener("submit", (event) => {
  event.preventDefault();
  const matches = username.value === "paguro-fixture"
    && password.value === "Paguro-fixture-only-2026!";
  result.textContent = matches ? "Dummy login matches." : "The dummy login does not match.";
  result.dataset.matches = String(matches);
});

document.getElementById("clear-login").addEventListener("click", () => {
  form.reset();
  result.textContent = "Waiting for the dummy login.";
  delete result.dataset.matches;
});
