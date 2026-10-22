// Admin dashboard: draw bar charts from /api/stats and filter the complaint table.
async function drawCharts() {
  const box = document.getElementById("charts");
  if (!box) return;
  const data = await (await fetch("/api/stats")).json();
  const sections = [["By status", data.status], ["By category", data.category], ["By hostel", data.hostel]];
  box.innerHTML = "";
  sections.forEach(([title, rows]) => {
    const max = Math.max(1, ...rows.map(r => r.n));
    const card = document.createElement("div");
    card.className = "card";
    card.innerHTML = "<strong>" + title + "</strong>" + rows.map(r =>
      '<div class="bar-row"><span class="bar-label">' + r.label + '</span><div class="bar" style="width:' +
      Math.round((r.n / max) * 100) + '%;min-width:4px"></div><span>' + r.n + "</span></div>").join("");
    box.appendChild(card);
  });
}

function applyFilters() {
  const status = document.getElementById("f-status").value;
  const prio = document.getElementById("f-prio").value;
  const text = document.getElementById("f-text").value.toLowerCase();
  document.querySelectorAll("#complaint-table tbody tr").forEach(tr => {
    const ok = (!status || tr.dataset.status === status) && (!prio || tr.dataset.prio === prio) &&
               (!text || tr.textContent.toLowerCase().includes(text));
    tr.style.display = ok ? "" : "none";
  });
}

document.addEventListener("DOMContentLoaded", () => {
  drawCharts();
  ["f-status", "f-prio", "f-text"].forEach(id => {
    const el = document.getElementById(id);
    if (el) el.addEventListener("input", applyFilters);
  });
  document.querySelectorAll("form[data-confirm]").forEach(f =>
    f.addEventListener("submit", e => { if (!confirm(f.dataset.confirm)) e.preventDefault(); }));
});
