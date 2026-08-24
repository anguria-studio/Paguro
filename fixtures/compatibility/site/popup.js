document.querySelector("#complete-popup").addEventListener("click", () => {
  localStorage.setItem("atoll-compatibility-popup", "completed");
  if (window.opener) {
    window.opener.postMessage(
      {
        source: "atoll-compatibility-fixture",
        frame: "Pop-up",
        message: "Stored its marker and requested window.close().",
      },
      window.location.origin
    );
  }
  window.close();
});
