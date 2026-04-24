(() => {
  function cellValue(row, index) {
    const cell = row.children[index];
    return cell ? cell.textContent.trim() : "";
  }

  function sortableValue(text) {
    const numeric = Number.parseFloat(text.replace(/[% ,]/g, ""));
    return Number.isNaN(numeric) ? text.toLowerCase() : numeric;
  }

  function sortTable(table, index, direction) {
    const body = table.tBodies[0];
    if (!body) return;

    const rows = Array.from(body.rows);
    rows.sort((left, right) => {
      const a = sortableValue(cellValue(left, index));
      const b = sortableValue(cellValue(right, index));
      if (a < b) return direction === "asc" ? -1 : 1;
      if (a > b) return direction === "asc" ? 1 : -1;
      return 0;
    });

    rows.forEach((row) => body.appendChild(row));
  }

  function installSortableTables() {
    document.querySelectorAll("table[data-sortable='true']").forEach((table) => {
      const headers = Array.from(table.tHead ? table.tHead.rows[0].cells : []);
      headers.forEach((header, index) => {
        header.dataset.sortableColumn = "true";
        header.addEventListener("click", () => {
          const nextDirection = header.dataset.sortDirection === "asc" ? "desc" : "asc";
          headers.forEach((cell) => delete cell.dataset.sortDirection);
          header.dataset.sortDirection = nextDirection;
          sortTable(table, index, nextDirection);
        });
      });
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", installSortableTables);
  } else {
    installSortableTables();
  }
})();
