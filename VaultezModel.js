.pragma library

// Case-insensitive substring filter over a list of {name, ...} rows.
function filterRows(rows, filterText, nameKey) {
  var list = Array.isArray(rows) ? rows : []
  var needle = String(filterText || "").trim().toLowerCase()
  if (needle === "") return list
  var key = nameKey || "name"
  return list.filter(function(row) {
    var value = row && row[key] !== undefined ? String(row[key]) : ""
    return value.toLowerCase().indexOf(needle) !== -1
  })
}

// Classify a vaultez-cli stderr blob into a state the panel knows how to
// render. "not logged in" is the fixed prefix of NotAuthenticatedError's
// message in lib/vaultez/errors.rb / client.rb.
function classifyError(stderrText) {
  var text = String(stderrText || "")
  if (/not logged in/i.test(text)) return "not-authenticated"
  return "generic"
}

// Fixed-width mask so the placeholder never leaks the real value's length.
function maskedValue() {
  return "••••••••"
}
