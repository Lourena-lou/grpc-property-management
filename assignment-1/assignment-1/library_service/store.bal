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
// Rule 3 is the one that reshapes the code. Previously `getAsset` returned a
// live reference and callers mutated it in place. Now it returns a copy, so
// every mutation must happen inside the lock, against the stored value.
//
// The payoff: with these functions isolated, the service's resource methods can
// be isolated too, and Ballerina will run requests genuinely in parallel
// instead of serialising them.
//
// Reference: https://ballerina.io/learn/by-example/isolated-variables/
// ============================================================================
import ballerina/time;

// ----------------------------------------------------------------------------
// THE STORE
// `isolated` (not `final`) — the compiler now guards every access.
// ----------------------------------------------------------------------------

# All library resources, keyed by their unique asset tag.
isolated table<Asset> key(assetTag) assetTable = table [];

# All registered institutions, keyed by their short code.
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

// ----------------------------------------------------------------------------
// ASSET LOOKUPS
// Each returns a CLONE. Mutating the result does not touch the store.
// ----------------------------------------------------------------------------

# Lists every asset in the system.
#
# + return - A copy of all assets, in insertion order
public isolated function getAllAssets() returns Asset[] {
    lock {
        return assetTable.toArray().clone();
    }
}

# Looks up a single asset by its tag.
#
# + assetTag - The tag to look up
# + return - A copy of the matching asset, or `()` if the tag is unknown
public isolated function getAsset(string assetTag) returns Asset? {
    lock {
        Asset? asset = assetTable[assetTag];
        return asset.clone();
    }
}

# Checks whether a tag is already in use.
#
# + assetTag - The tag to test
# + return - `true` if an asset with this tag exists
public isolated function assetExists(string assetTag) returns boolean {
    lock {
        return assetTable.hasKey(assetTag);
    }
}

# Finds assets filtered by institution and/or site. Passing `()` for either
# means "do not filter on this"; `()` for both returns everything.
#
# + institution - Institution name to match, or `()` for any
# + site - Site or campus to match, or `()` for any
# + return - Copies of the assets satisfying both filters
public isolated function findAssets(string? institution, string? site) returns Asset[] {
    lock {
        Asset[] matches = from Asset asset in assetTable
            where institution is () || asset.institution == institution
            where site is () || asset.site == site
            select asset;
        return matches.clone();
    }
}

# Finds all assets currently in a given state.
#
# + status - The status to match
# + return - Copies of the assets whose status equals `status`
public isolated function findAssetsByStatus(AssetStatus status) returns Asset[] {
    lock {
        Asset[] matches = from Asset asset in assetTable
            where asset.status == status
            select asset;
        return matches.clone();
    }
}

# Finds assets with at least one schedule whose due date has already passed.
#
# The inner `from` walks each asset's schedules; `limit 1` stops at the first
# overdue schedule, since we only need to know one exists.
#
# + return - Copies of the assets with one or more overdue schedules
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

// ----------------------------------------------------------------------------
// ASSET MUTATIONS
// Mutations happen INSIDE the lock, against the stored value.
// ----------------------------------------------------------------------------

# Adds a new asset to the store.
#
# + asset - The asset to add
# + return - A copy of the stored asset, or an error if the tag is in use
public isolated function addAsset(Asset asset) returns Asset|error {
    lock {
        // Clone on the way IN as well: the caller must not retain a reference
        // to something now living inside the protected table.
        Asset stored = asset.clone();
        if assetTable.hasKey(stored.assetTag) {
            return error(string `Asset '${stored.assetTag}' already exists`);
        }
        assetTable.add(stored);
        return stored.clone();
    }
}

# Overwrites the mutable fields of an existing asset. The key is never touched.
#
# + assetTag - Tag of the asset to update
# + update - Replacement values for the mutable fields
# + return - A copy of the updated asset, or an error if the tag is unknown
public isolated function updateAsset(string assetTag, AssetUpdate update)
        returns Asset|error {
    lock {
        Asset? existing = assetTable[assetTag];
        if existing is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        AssetUpdate u = update.clone();
        existing.name = u.name;
        existing.description = u.description;
        existing.institution = u.institution;
        existing.site = u.site;
        existing.status = u.status;
        existing.dateAcquired = u.dateAcquired;
        return existing.clone();
    }
}

# Removes an asset from the store.
#
# `removeIfHasKey` returns `()` instead of panicking when the key is absent.
#
# + assetTag - Tag of the asset to remove
# + return - A copy of the removed asset, or an error if the tag is unknown
public isolated function deleteAsset(string assetTag) returns Asset|error {
    lock {
        Asset? removed = assetTable.removeIfHasKey(assetTag);
        if removed is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        return removed.clone();
    }
}

// ----------------------------------------------------------------------------
// LOANING AND BOOKING
// The check and the write happen in ONE lock — this is the whole point.
// Splitting them would allow two concurrent requests to both see AVAILABLE
// and both loan the same asset.
// ----------------------------------------------------------------------------

# Loans an asset or books a space. Spaces become `OCCUPIED`, everything else
# becomes `LOANED_OUT`.
#
# + assetTag - Tag of the asset to loan
# + isSpace - `true` for a room or lab, so the state becomes `OCCUPIED`
# + return - A copy of the updated asset, or an error if unknown or unavailable
public isolated function loanAsset(string assetTag, boolean isSpace = false)
        returns Asset|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        if asset.status != AVAILABLE {
            return error(string `Asset '${assetTag}' is not available (currently ${asset.status})`);
        }
        asset.status = isSpace ? OCCUPIED : LOANED_OUT;
        return asset.clone();
    }
}

# Returns a loaned asset or frees an occupied space.
#
# + assetTag - Tag of the asset to return
# + return - A copy of the updated asset, or an error if unknown or not out
public isolated function returnAsset(string assetTag) returns Asset|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        if asset.status != LOANED_OUT && asset.status != OCCUPIED {
            return error(string `Asset '${assetTag}' is not currently loaned out`);
        }
        asset.status = AVAILABLE;
        return asset.clone();
    }
}

// ----------------------------------------------------------------------------
// COMPONENTS
// ----------------------------------------------------------------------------

# Adds a component to an asset.
#
# + assetTag - Tag of the owning asset
# + component - The component to add
# + return - A copy of the added component, or an error if the asset or id is invalid
public isolated function addComponent(string assetTag, Component component)
        returns Component|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        Component stored = component.clone();
        foreach Component c in asset.components {
            if c.compId == stored.compId {
                return error(string `Component '${stored.compId}' already exists on this asset`);
            }
        }
        asset.components.push(stored);
        return stored.clone();
    }
}

# Removes a component from an asset.
#
# + assetTag - Tag of the owning asset
# + compId - Identifier of the component to remove
# + return - A copy of the removed component, or an error if either id is unknown
public isolated function removeComponent(string assetTag, string compId)
        returns Component|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        int index = 0;
        foreach Component c in asset.components {
            if c.compId == compId {
                Component removed = asset.components.remove(index);
                return removed.clone();
            }
            index += 1;
        }
        return error(string `Component '${compId}' not found on asset '${assetTag}'`);
    }
}

// ----------------------------------------------------------------------------
// SCHEDULES
// ----------------------------------------------------------------------------

# Adds a maintenance, servicing, or booking schedule to an asset.
#
# + assetTag - Tag of the owning asset
# + schedule - The schedule to add
# + return - A copy of the added schedule, or an error if the asset or id is invalid
public isolated function addSchedule(string assetTag, Schedule schedule)
        returns Schedule|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        Schedule stored = schedule.clone();
        foreach Schedule s in asset.schedules {
            if s.scheduleId == stored.scheduleId {
                return error(string `Schedule '${stored.scheduleId}' already exists on this asset`);
            }
        }
        asset.schedules.push(stored);
        return stored.clone();
    }
}

# Replaces an existing schedule in place.
#
# + assetTag - Tag of the owning asset
# + scheduleId - Identifier of the schedule to replace
# + updated - Replacement schedule
# + return - A copy of the updated schedule, or an error if either id is unknown
public isolated function updateSchedule(string assetTag, string scheduleId,
        Schedule updated) returns Schedule|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        Schedule replacement = updated.clone();
        int index = 0;
        foreach Schedule s in asset.schedules {
            if s.scheduleId == scheduleId {
                asset.schedules[index] = replacement;
                return replacement.clone();
            }
            index += 1;
        }
        return error(string `Schedule '${scheduleId}' not found on asset '${assetTag}'`);
    }
}

# Removes a schedule from an asset.
#
# + assetTag - Tag of the owning asset
# + scheduleId - Identifier of the schedule to remove
# + return - A copy of the removed schedule, or an error if either id is unknown
public isolated function removeSchedule(string assetTag, string scheduleId)
        returns Schedule|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        int index = 0;
        foreach Schedule s in asset.schedules {
            if s.scheduleId == scheduleId {
                Schedule removed = asset.schedules.remove(index);
                return removed.clone();
            }
            index += 1;
        }
        return error(string `Schedule '${scheduleId}' not found on asset '${assetTag}'`);
    }
}

// ----------------------------------------------------------------------------
// WORK ORDERS
// Same shape as schedules, but these own a nested list of tasks.
// ----------------------------------------------------------------------------

# Opens a work order against a faulty asset.
#
# + assetTag - Tag of the owning asset
# + workOrder - The work order to open
# + return - A copy of the created work order, or an error if the asset or id is invalid
public isolated function addWorkOrder(string assetTag, WorkOrder workOrder)
        returns WorkOrder|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        WorkOrder stored = workOrder.clone();
        foreach WorkOrder w in asset.workOrders {
            if w.orderId == stored.orderId {
                return error(string `Work order '${stored.orderId}' already exists on this asset`);
            }
        }
        asset.workOrders.push(stored);
        return stored.clone();
    }
}

# Replaces an existing work order, including its task list.
#
# + assetTag - Tag of the owning asset
# + orderId - Identifier of the work order to replace
# + updated - Replacement work order
# + return - A copy of the updated work order, or an error if either id is unknown
public isolated function updateWorkOrder(string assetTag, string orderId,
        WorkOrder updated) returns WorkOrder|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        WorkOrder replacement = updated.clone();
        int index = 0;
        foreach WorkOrder w in asset.workOrders {
            if w.orderId == orderId {
                asset.workOrders[index] = replacement;
                return replacement.clone();
            }
            index += 1;
        }
        return error(string `Work order '${orderId}' not found on asset '${assetTag}'`);
    }
}

# Moves a work order to a new state, e.g. `CLOSED`, without touching its tasks.
#
# + assetTag - Tag of the owning asset
# + orderId - Identifier of the work order
# + status - The state to move the work order into
# + return - A copy of the updated work order, or an error if either id is unknown
public isolated function setWorkOrderStatus(string assetTag, string orderId,
        WorkOrderStatus status) returns WorkOrder|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        foreach WorkOrder w in asset.workOrders {
            if w.orderId == orderId {
                w.status = status;
                return w.clone();
            }
        }
        return error(string `Work order '${orderId}' not found on asset '${assetTag}'`);
    }
}

# Removes a work order and everything under it.
#
# + assetTag - Tag of the owning asset
# + orderId - Identifier of the work order to remove
# + return - A copy of the removed work order, or an error if either id is unknown
public isolated function removeWorkOrder(string assetTag, string orderId)
        returns WorkOrder|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        int index = 0;
        foreach WorkOrder w in asset.workOrders {
            if w.orderId == orderId {
                WorkOrder removed = asset.workOrders.remove(index);
                return removed.clone();
            }
            index += 1;
        }
        return error(string `Work order '${orderId}' not found on asset '${assetTag}'`);
    }
}

// ----------------------------------------------------------------------------
// TASKS — one level deeper: find the work order, then the task inside it.
// ----------------------------------------------------------------------------

# Adds a sub-task to an open work order, e.g. "replace screen".
#
# + assetTag - Tag of the owning asset
# + orderId - Identifier of the parent work order
# + task - The task to add
# + return - A copy of the added task, or an error if any id is invalid
public isolated function addTask(string assetTag, string orderId, Task task)
        returns Task|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        Task stored = task.clone();
        foreach WorkOrder w in asset.workOrders {
            if w.orderId == orderId {
                foreach Task t in w.tasks {
                    if t.taskId == stored.taskId {
                        return error(string `Task '${stored.taskId}' already exists on this work order`);
                    }
                }
                w.tasks.push(stored);
                return stored.clone();
            }
        }
        return error(string `Work order '${orderId}' not found on asset '${assetTag}'`);
    }
}

# Removes a sub-task from a work order.
#
# + assetTag - Tag of the owning asset
# + orderId - Identifier of the parent work order
# + taskId - Identifier of the task to remove
# + return - A copy of the removed task, or an error if any id is unknown
public isolated function removeTask(string assetTag, string orderId, string taskId)
        returns Task|error {
    lock {
        Asset? asset = assetTable[assetTag];
        if asset is () {
            return error(string `Asset '${assetTag}' not found`);
        }
        foreach WorkOrder w in asset.workOrders {
            if w.orderId == orderId {
                int index = 0;
                foreach Task t in w.tasks {
                    if t.taskId == taskId {
                        Task removed = w.tasks.remove(index);
                        return removed.clone();
                    }
                    index += 1;
                }
                return error(string `Task '${taskId}' not found on work order '${orderId}'`);
            }
        }
        return error(string `Work order '${orderId}' not found on asset '${assetTag}'`);
    }
}

// ----------------------------------------------------------------------------
// INSTITUTIONS
// ----------------------------------------------------------------------------

# Lists every registered institution.
#
# + return - Copies of all institutions, in insertion order
public isolated function getAllInstitutions() returns Institution[] {
    lock {
        return institutionTable.toArray().clone();
    }
}

# Checks whether an institution code is registered.
#
# + institutionId - The code to test
# + return - `true` if the institution exists
public isolated function institutionExists(string institutionId) returns boolean {
    lock {
        return institutionTable.hasKey(institutionId);
    }
}

# Registers a new institution.
#
# + institution - The institution to add
# + return - A copy of the stored institution, or an error if the id is in use
public isolated function addInstitution(Institution institution)
        returns Institution|error {
    lock {
        Institution stored = institution.clone();
        if institutionTable.hasKey(stored.institutionId) {
            return error(string `Institution '${stored.institutionId}' already exists`);
        }
        institutionTable.add(stored);
        return stored.clone();
    }
}

# Removes an institution from the listing.
#
# Refuses to remove an institution that still owns assets, rather than leaving
# those assets pointing at something that no longer exists.
#
# Note both tables are read here, so both locks are taken. Ballerina permits
# nested locks; keep the ordering consistent across the codebase to avoid
# deadlock.
#
# + institutionId - Short code of the institution to remove
# + return - A copy of the removed institution, or an error if unknown or in use
public isolated function removeInstitution(string institutionId)
        returns Institution|error {
    string institutionName;
    lock {
        Institution? institution = institutionTable[institutionId];
        if institution is () {
            return error(string `Institution '${institutionId}' not found`);
        }
        institutionName = institution.name;
    }

    int ownedCount;
    lock {
        ownedCount = (from Asset a in assetTable
            where a.institution == institutionName
            select a).length();
    }
    if ownedCount > 0 {
        return error(string `Cannot remove '${institutionName}': ${ownedCount} asset(s) still assigned`);
    }

    lock {
        Institution? removed = institutionTable.removeIfHasKey(institutionId);
        if removed is () {
            return error(string `Institution '${institutionId}' not found`);
        }
        return removed.clone();
    }
}

// ----------------------------------------------------------------------------
// SEED DATA
// ----------------------------------------------------------------------------

# Populates the store with sample institutions and assets. Safe to call twice:
# duplicate inserts fail silently rather than crashing startup.
public isolated function seedData() {
    Institution[] institutions = [
        {institutionId: "NUST", name: "Namibia University of Science and Technology"},
        {institutionId: "UNAM", name: "University of Namibia"}
    ];
    foreach Institution i in institutions {
        Institution|error result = addInstitution(i);
        if result is error {
            // Seeding twice is harmless; ignore.
        }
    }

    Asset[] assets = [
        {
            assetTag: "NUST-LIB-3DP-001",
            name: "Pro-Series 3D Printer",
            description: "High-precision laboratory printer for prototype development.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Innovation Lab",
            status: AVAILABLE,
            dateAcquired: "2024-03-10",
            components: [
                {
                    compId: "C101",
                    name: "High-Torque Stepper Motor",
                    description: "Main motor for X-axis movement."
                }
            ],
            schedules: [
                {
                    scheduleId: "SCH-882",
                    'type: MAINTENANCE,
                    // Deliberately in the past so it shows on the overdue view.
                    dueDate: "2026-06-01",
                    description: "Quarterly calibration and nozzle cleaning."
                }
            ],
            workOrders: [
                {
                    orderId: "WO-554",
                    status: OPEN,
                    description: "Nozzle heat-bed failure",
                    tasks: [{taskId: "T1", description: "Check thermal sensor connectivity."}]
                }
            ]
        },
        {
            assetTag: "NUST-LIB-LAP-014",
            name: "Dell Latitude Laptop",
            description: "Student loan laptop.",
            institution: "Namibia University of Science and Technology",
            site: "Main Campus - Library",
            status: AVAILABLE,
            dateAcquired: "2025-01-20"
        },
        {
            assetTag: "UNAM-RM-MTG-002",
            name: "Meeting Room B",
            description: "Seats 12, projector and whiteboard.",
            institution: "University of Namibia",
            site: "Windhoek Campus - Block C",
            status: AVAILABLE,
            dateAcquired: "2023-08-01"
        }
    ];
    foreach Asset a in assets {
        Asset|error result = addAsset(a);
        if result is error {
            // Already seeded; ignore.
        }
    }
}
