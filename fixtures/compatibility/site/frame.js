const frameRole = document.body.dataset.frameRole || "Frame";

function report(message) {
  window.parent.postMessage(
    {
      source: "paguro-compatibility-fixture",
      frame: frameRole,
      message,
    },
    "*"
  );
}

document.querySelector("button").addEventListener("click", async () => {
  report("Notification button clicked.");
  try {
    await Notification.requestPermission();
    new Notification(`${frameRole} notification`, {
      body: `This event came from the ${frameRole.toLowerCase()}.`,
      tag: frameRole.toLowerCase().replaceAll(" ", "-"),
    });
    report("Notification requested.");
  } catch (error) {
    report(`Notification failed: ${error.message}`);
  }
});
