document.querySelector("#complete-popup").addEventListener("click", () => {
  localStorage.setItem("blatta-compatibility-popup", "completed");
  if (window.opener) {
    window.opener.postMessage(
      {
        source: "blatta-compatibility-fixture",
        frame: "Pop-up",
        message: "Stored its marker and requested window.close().",
      },
      window.location.origin
    );
  }
  window.close();
});
