// ============================================================================
// store.bal — In-memory data store and the logic that operates on it.
//
// CONCURRENCY MODEL
// -----------------
// The tables are declared `isolated`, which makes them Ballerina's equivalent
// of state protected by a mutex. Three rules follow, and the compiler enforces
// all of them:
//
//   1. An `isolated` variable may only be touched inside a `lock` block.
//   2. Every function that touches one must itself be `isolated`.
//   3. Values crossing the lock boundary — in or out — must be IMMUTABLE or a
//      CLONE. You may never hand out a reference to the protected state.
//
// Rule 3 is the one that reshapes the code: reads return a copy, so every
// mutation must happen inside the lock, against the stored value.
//
// Reference: https://ballerina.io/learn/by-example/isolated-variables/
// ============================================================================
import ballerina/time;

// ----------------------------------------------------------------------------
// DATE HELPER
// Dates are ISO "YYYY-MM-DD" strings. Because ISO dates are zero-padded and
// ordered big-endian, lexicographic string comparison IS chronological
// comparison — "2026-09-01" < "2026-09-10" holds as text and as dates.
// ----------------------------------------------------------------------------

# Gets the current UTC date.
#
# + return - Today's date as an ISO "YYYY-MM-DD" string
public isolated function today() returns string {
    string timestamp = time:utcToString(time:utcNow());
    return timestamp.substring(0, 10);
}
