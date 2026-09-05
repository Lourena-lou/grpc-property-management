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
isolated table<Asset> key(assetTag) assetTable = table [];

isolated table<Institution> key(institutionId) institutionTable = table [];
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
public isolated function getAllAssets() returns Asset[] {
    lock {
        return assetTable.toArray().clone();
    }
}

public isolated function getAsset(string assetTag) returns Asset? {
    lock {
        Asset? asset = assetTable[assetTag];
        return asset.clone();
    }
}

public isolated function assetExists(string assetTag) returns boolean {
    lock {
        return assetTable.hasKey(assetTag);
    }
}

public isolated function findAssets(string? institution, string? site) returns Asset[] {
    lock {
        Asset[] matches = from Asset asset in assetTable
            where institution is () || asset.institution == institution
            where site is () || asset.site == site
            select asset;
        return matches.clone();
    }
}

public isolated function findAssetsByStatus(AssetStatus status) returns Asset[] {
    lock {
        Asset[] matches = from Asset asset in assetTable
            where asset.status == status
            select asset;
        return matches.clone();
    }
}

public isolated function findOverdueAssets() returns Asset[] {
    string currentDate = today();
    lock {
        Asset[] matches = from Asset asset in assetTable
            where (from Schedule s in asset.schedules
                where s.dueDate < currentDate
                limit 1
                select s).length() > 0
            select asset;
        return matches.clone();
    }
}

public isolated function addAsset(Asset asset) returns Asset|error {
    lock {
        Asset stored = asset.clone();
        if assetTable.hasKey(stored.assetTag) {
            return error(string `Asset '${stored.assetTag}' already exists`);
        }
        assetTable.add(stored);
        return stored.clone();
    }
}

public isolated function deleteAsset(string assetTag) returns Asset|error {
    lock {
        Asset? removed = assetTable.removeIfHasKey(assetTag);
        if removed is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        return removed.clone();
    }
}