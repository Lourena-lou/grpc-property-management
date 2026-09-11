// ============================================================================
// types.bal — Client-side copy of the data model.
//
// The client is a SEPARATE PACKAGE, so it cannot see the service's types.
// These records must structurally match the service's, because Ballerina binds
// the JSON response onto them by shape (structural typing — Lesson 02).
//
// Note there are no http:NotFound records here: the client RECEIVES status
// codes, it does not produce them.
// ============================================================================

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

# A single unit of work inside a work order.
#
# + taskId - Identifier, unique within the parent work order
# + description - What the technician must do
public type Task record {|
    string taskId;
    string description;
|};

# A repair or fault job raised against an asset.
#
# + orderId - Identifier, unique within the parent asset
# + status - Current state of the job
# + description - Summary of the fault
# + tasks - Sub-tasks required to complete the job
public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    Task[] tasks = [];
|};

# A physical part of a complex asset.
#
# + compId - Identifier, unique within the parent asset
# + name - Human-readable part name
# + description - What the part does
public type Component record {|
    string compId;
    string name;
    string description;
|};

# A planned maintenance, servicing, or booking event.
#
# + scheduleId - Identifier, unique within the parent asset
# + 'type - Category of the event
# + dueDate - Date the event falls due, ISO "YYYY-MM-DD"
# + description - What is scheduled to happen
public type Schedule record {|
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string description;
|};

# A library resource: a book, a laptop, a lab, or a meeting room.
#
# + assetTag - Globally unique identifier
# + name - Human-readable resource name
# + description - Details of the resource
# + institution - Owning institution's full name
# + site - Campus or site where the resource is held
# + status - Current availability state
# + dateAcquired - Acquisition date, ISO "YYYY-MM-DD"
# + components - Constituent parts of a complex asset
# + schedules - Planned maintenance and booking events
# + workOrders - Open and historical repair jobs
public type Asset record {|
    readonly string assetTag;
    string name;
    string description;
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
|};

# An institution registered in the ministry's listing.
#
# + institutionId - Short code, e.g. "NUST"
# + name - Full institution name
public type Institution record {|
    readonly string institutionId;
    string name;
|};
