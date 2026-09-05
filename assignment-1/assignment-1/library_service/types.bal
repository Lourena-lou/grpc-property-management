import ballerina/http; 
// ----------------------------------------------------------------------------
// ENUMS
// The brief names exactly four asset states.
// ----------------------------------------------------------------------------

# Lifecycle state of a library resource.
public enum AssetStatus {
    AVAILABLE,
    LOANED_OUT,
    OCCUPIED,
    UNDER_MAINTENANCE,
    DISPOSED
}

# Category of a planned event against an asset.
public enum ScheduleType {
    MAINTENANCE,
    SERVICING,
    BOOKING
}

# Lifecycle state of a repair job.
public enum WorkOrderStatus {
    OPEN,
    IN_PROGRESS,
    CLOSED
}

// ----------------------------------------------------------------------------
// NESTED ENTITIES
// Innermost first, because each one is used by the next.
// All closed records ({| |}) — we want the compiler rejecting unknown fields.
// ----------------------------------------------------------------------------

# A single unit of work inside a work order, e.g. "replace screen".
#
# + taskId - Identifier, unique within the parent work order
# + description - What the technician must do
public type Task record {|
    string taskId;
    string description;
|};

# A repair job raised against an asset. Owns its own list of tasks.
#
# + orderId - Identifier, unique within the parent asset
# + status - Current state of the job; defaults to `OPEN`
# + description - Summary of the fault
# + tasks - Sub-tasks required to complete the job; defaults to empty
public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    Task[] tasks = [];
|};

# A physical part of a complex asset, e.g. the stepper motor in a 3D printer.
#
# + compId - Identifier, unique within the parent asset
# + name - Human-readable part name
# + description - What the part does
public type Component record {|
    string compId;
    string name;
    string description;
|};

# A planned maintenance, servicing, or booking event for an asset.
#
# + scheduleId - Identifier, unique within the parent asset
# + 'type - Category of the event
# + dueDate - Date the event falls due, ISO "YYYY-MM-DD"
# + description - What is scheduled to happen
public type Schedule record {|
    string scheduleId;
    // `type` is a RESERVED KEYWORD in Ballerina.
    ScheduleType 'type;
    // Date format "YYYY-MM-DD".
    string dueDate;
    string description;
|};

// ----------------------------------------------------------------------------
// THE ROOT ENTITY
// ----------------------------------------------------------------------------

# A library resource: a book, a laptop, a lab, or a meeting room.
#
# + assetTag - Globally unique identifier; the table key, hence `readonly`
# + name - Human-readable resource name
# + description - Details of the resource
# + institution - Owning institution's full name
# + site - Campus or site where the resource is held
# + status - Current availability state; defaults to `AVAILABLE`
# + dateAcquired - Acquisition date, ISO "YYYY-MM-DD"
# + components - Constituent parts of a complex asset; defaults to empty
# + schedules - Planned maintenance and booking events; defaults to empty
# + workOrders - Open and historical repair jobs; defaults to empty
public type Asset record {|
    // `readonly` is REQUIRED for a field used as a table key. It guarantees the
    // key can never change underneath the table's index.
    readonly string assetTag;
    string name;
    string description;
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    // Defaults let a client POST a minimal asset without these three arrays.
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
|};

# An institution registered in the ministry's listing.
# 
# + institutionId - Short code, e.g. "NUST"; the table key, hence `readonly`
# + name - Full institution name, as it appears on assets
public type Institution record {|
    readonly string institutionId;
    string name;
|};
// ----------------------------------------------------------------------------
// UPDATE PAYLOAD
// A PUT must not let the caller rewrite the primary key, so this is Asset
// WITHOUT assetTag.
// ----------------------------------------------------------------------------

# Mutable fields of an asset, used as the body of a PUT. Deliberately excludes
# `assetTag` so an update cannot change the primary key.
#
# + name - Replacement resource name
# + description - Replacement description
# + institution - Replacement owning institution
# + site - Replacement campus or site
# + status - Replacement availability state
# + dateAcquired - Replacement acquisition date, ISO "YYYY-MM-DD"
public type AssetUpdate record {|
    string name;
    string description;
    string institution;
    string site;
    AssetStatus status;
    string dateAcquired;
|};

// ----------------------------------------------------------------------------
// HTTP ERROR RESPONSES
//
// This is the idiomatic Ballerina pattern from the official REST guide:
// `*http:NotFound` includes the http:NotFound type, which makes this record a
// SUBTYPE of it. Returning one of these from a resource function sets the HTTP
// status code automatically.
// ----------------------------------------------------------------------------

# Standard error body so every failure looks the same to the client.
#
# + errmsg - Human-readable explanation of what went wrong
public type ErrorMsg record {|
    string errmsg;
|};

# 404 — the requested asset, component, schedule, or work order does not exist.
#
# + body - Explanation of which resource was not found
public type NotFoundError record {|
    *http:NotFound;
    ErrorMsg body;
|};

# 409 — duplicate `assetTag`, or an operation conflicting with current state
# such as loaning an asset that is already `LOANED_OUT`.
#
# + body - Explanation of the conflict
public type ConflictError record {|
    *http:Conflict;
    ErrorMsg body;
|};

# 400 — the request is malformed or violates a business rule.
#
# + body - Explanation of why the request was rejected
public type BadRequestError record {|
    *http:BadRequest;
    ErrorMsg body;
|};