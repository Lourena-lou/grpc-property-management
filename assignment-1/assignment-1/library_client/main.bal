// ============================================================================
// main.bal — Command-line client for the Library & Resource Management System.
//
// Implements the five views required by the brief:
//   1. Loaning & Booking      2. Global View       3. Campus View
//   4. Overdue Dashboard      5. Schedule Manager
//
// Run the service FIRST (bal run in ../library_service), then run this.
// ============================================================================
import ballerina/http;
import ballerina/io;

// The service's base URL. `check` here means a bad URL fails at startup
// rather than on first use.
final http:Client libraryClient = check new ("http://localhost:9090/library");

// A plain divider, built once rather than rebuilt on every call.
const string DIVIDER = "============================================================";

// ----------------------------------------------------------------------------
// PRESENTATION HELPERS
// ----------------------------------------------------------------------------

# Prints a section heading.
#
# + title - Heading text
function header(string title) {
    io:println("\n" + DIVIDER);
    io:println("  " + title);
    io:println(DIVIDER);
}

# Prints one asset as a short summary block.
#
# + asset - The asset to display
function printAssetLine(Asset asset) {
    io:println(string `  ${asset.assetTag}`);
    io:println(string `    ${asset.name}  [${asset.status}]`);
    io:println(string `    ${asset.institution} - ${asset.site}`);
}

# Prints an asset with all of its nested detail.
#
# + asset - The asset to display
function printAssetDetail(Asset asset) {
    printAssetLine(asset);
    io:println(string `    Acquired: ${asset.dateAcquired}`);
    io:println(string `    ${asset.description}`);

    if asset.components.length() > 0 {
        io:println("    Components:");
        foreach Component c in asset.components {
            io:println(string `      - [${c.compId}] ${c.name}`);
        }
    }
    if asset.schedules.length() > 0 {
        io:println("    Schedules:");
        foreach Schedule s in asset.schedules {
            io:println(string `      - [${s.scheduleId}] ${s.'type} due ${s.dueDate}`);
        }
    }
    if asset.workOrders.length() > 0 {
        io:println("    Work orders:");
        foreach WorkOrder w in asset.workOrders {
            io:println(string `      - [${w.orderId}] ${w.status}: ${w.description}`);
            foreach Task t in w.tasks {
                io:println(string `          * ${t.taskId} ${t.description}`);
            }
        }
    }
}

# Prints a list of assets, or a placeholder when empty.
#
# + assets - Assets to display
function printAssets(Asset[] assets) {
    if assets.length() == 0 {
        io:println("  (none)");
        return;
    }
    foreach Asset a in assets {
        printAssetLine(a);
        io:println("");
    }
    io:println(string `  ${assets.length()} asset(s).`);
}

# Reports a failed request in a readable way.
#
# When a resource returns 4xx, the Ballerina client surfaces it as an error
# rather than a value, so every call site has to handle it explicitly.
#
# + e - The error returned by the client call
function reportError(error e) {
    io:println("  Request failed: " + e.message());
}

// ----------------------------------------------------------------------------
// VIEW 2 — GLOBAL VIEW
// ----------------------------------------------------------------------------

# Lists every asset across the ministry.
function globalView() {
    header("GLOBAL VIEW - All assets across the ministry");
    Asset[]|error assets = libraryClient->/assets;
    if assets is error {
        reportError(assets);
        return;
    }
    printAssets(assets);
}

// ----------------------------------------------------------------------------
// VIEW 3 — CAMPUS VIEW
// ----------------------------------------------------------------------------

# Filters assets by institution and optionally by site.
function campusView() {
    header("CAMPUS VIEW - Filter by institution and site");

    Institution[]|error institutions = libraryClient->/institutions;
    if institutions is error {
        reportError(institutions);
        return;
    }
    io:println("  Registered institutions:");
    foreach Institution i in institutions {
        io:println(string `    ${i.institutionId} - ${i.name}`);
    }

    string institution = io:readln("\n  Institution name (blank for all): ").trim();
    string site = io:readln("  Site/campus (blank for all): ").trim();

    // Build the query only from the filters actually supplied. Sending an
    // empty string would filter for assets whose institution IS "".
    Asset[]|error assets;
    if institution == "" && site == "" {
        assets = libraryClient->/assets;
    } else if site == "" {
        assets = libraryClient->/assets(institution = institution);
    } else if institution == "" {
        assets = libraryClient->/assets(site = site);
    } else {
        assets = libraryClient->/assets(institution = institution, site = site);
    }

    if assets is error {
        reportError(assets);
        return;
    }
    io:println("");
    printAssets(assets);
}

// ----------------------------------------------------------------------------
// VIEW 4 — OVERDUE DASHBOARD
// ----------------------------------------------------------------------------

# Shows assets whose maintenance schedules have lapsed.
function overdueDashboard() {
    header("OVERDUE DASHBOARD - Items past their due date");
    Asset[]|error assets = libraryClient->/assets/overdue;
    if assets is error {
        reportError(assets);
        return;
    }
    if assets.length() == 0 {
        io:println("  Nothing overdue.");
        return;
    }
    foreach Asset a in assets {
        printAssetDetail(a);
        io:println("");
    }
    io:println(string `  ${assets.length()} asset(s) need attention.`);
}

// ----------------------------------------------------------------------------
// VIEW 1 — LOANING & BOOKING
// ----------------------------------------------------------------------------

# Loans an asset, books a space, or processes a return.
function loanAndBook() {
    header("LOANING & BOOKING");

    Asset[]|error available = libraryClient->/assets(status = "AVAILABLE");
    if available is error {
        reportError(available);
        return;
    }
    io:println("  Currently available:");
    printAssets(available);

    io:println("\n  1) Loan an asset");
    io:println("  2) Book a room or lab");
    io:println("  3) Return an asset");
    string choice = io:readln("  Choose: ").trim();

    if choice == "3" {
        string tag = io:readln("  Asset tag to return: ").trim();
        Asset|error returned = libraryClient->/assets/[tag]/'return.post(());
        if returned is error {
            reportError(returned);
            return;
        }
        io:println(string `  Returned. '${returned.name}' is now ${returned.status}.`);
        return;
    }

    if choice != "1" && choice != "2" {
        io:println("  Unknown choice.");
        return;
    }

    boolean isSpace = choice == "2";
    string tag = io:readln("  Asset tag: ").trim();
    Asset|error result = libraryClient->/assets/[tag]/loan.post((), isSpace = isSpace);
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Done. '${result.name}' is now ${result.status}.`);
}

// ----------------------------------------------------------------------------
// VIEW 5 — SCHEDULE MANAGER
// ----------------------------------------------------------------------------

# Adds, updates, or removes servicing schedules on an asset.
function scheduleManager() {
    header("SCHEDULE MANAGER");

    string tag = io:readln("  Asset tag: ").trim();
    Asset|error asset = libraryClient->/assets/[tag];
    if asset is error {
        reportError(asset);
        return;
    }

    io:println(string `${"\n"}  ${asset.name}`);
    if asset.schedules.length() == 0 {
        io:println("  No schedules yet.");
    } else {
        io:println("  Existing schedules:");
        foreach Schedule s in asset.schedules {
            io:println(string `    [${s.scheduleId}] ${s.'type} due ${s.dueDate} - ${s.description}`);
        }
    }

    io:println("\n  1) Add a schedule");
    io:println("  2) Update a schedule");
    io:println("  3) Remove a schedule");
    string choice = io:readln("  Choose: ").trim();

    if choice == "3" {
        string scheduleId = io:readln("  Schedule ID to remove: ").trim();
        Schedule|error removed = libraryClient->/assets/[tag]/schedules/[scheduleId].delete();
        if removed is error {
            reportError(removed);
            return;
        }
        io:println(string `  Removed '${removed.scheduleId}'.`);
        return;
    }

    if choice != "1" && choice != "2" {
        io:println("  Unknown choice.");
        return;
    }

    string scheduleId = io:readln("  Schedule ID: ").trim();
    string typeInput = io:readln("  Type (MAINTENANCE / SERVICING / BOOKING): ").trim();
    // The enum is a union of string constants, so `is` narrows a raw string
    // straight into ScheduleType — no parsing or lookup table needed.
    if typeInput !is ScheduleType {
        io:println("  Invalid type.");
        return;
    }
    string dueDate = io:readln("  Due date (YYYY-MM-DD): ").trim();
    string description = io:readln("  Description: ").trim();

    Schedule schedule = {
        scheduleId: scheduleId,
        'type: typeInput,
        dueDate: dueDate,
        description: description
    };

    Schedule|error result;
    if choice == "1" {
        result = libraryClient->/assets/[tag]/schedules.post(schedule);
    } else {
        result = libraryClient->/assets/[tag]/schedules/[scheduleId].put(schedule);
    }

    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Saved schedule '${result.scheduleId}'.`);
}

// ----------------------------------------------------------------------------
// WORK ORDER MANAGER
// Opens, updates, closes, and deletes work orders, plus their sub-tasks.
// ----------------------------------------------------------------------------

# Manages work orders and their tasks for a single asset.
function workOrderManager() {
    header("WORK ORDER MANAGER");

    string tag = io:readln("  Asset tag: ").trim();
    Asset|error asset = libraryClient->/assets/[tag];
    if asset is error {
        reportError(asset);
        return;
    }

    io:println(string `${"\n"}  ${asset.name}  [${asset.status}]`);
    if asset.workOrders.length() == 0 {
        io:println("  No work orders on this asset.");
    } else {
        io:println("  Existing work orders:");
        foreach WorkOrder w in asset.workOrders {
            io:println(string `    [${w.orderId}] ${w.status} - ${w.description}`);
            foreach Task t in w.tasks {
                io:println(string `        * ${t.taskId}: ${t.description}`);
            }
        }
    }

    io:println("\n  1) Open a work order");
    io:println("  2) Update a work order's description");
    io:println("  3) Change a work order's status");
    io:println("  4) Delete a work order");
    io:println("  5) Add a task");
    io:println("  6) Remove a task");
    string choice = io:readln("  Choose: ").trim();

    match choice {
        "1" => {
            openWorkOrder(tag);
        }
        "2" => {
            editWorkOrder(tag, asset);
        }
        "3" => {
            changeWorkOrderStatus(tag);
        }
        "4" => {
            deleteWorkOrder(tag);
        }
        "5" => {
            addWorkOrderTask(tag);
        }
        "6" => {
            removeWorkOrderTask(tag);
        }
        _ => {
            io:println("  Unknown choice.");
        }
    }
}

# Opens a new work order against an asset.
#
# + tag - Asset tag to raise the work order against
function openWorkOrder(string tag) {
    string orderId = io:readln("  Work order ID: ").trim();
    string description = io:readln("  Fault description: ").trim();

    WorkOrder workOrder = {
        orderId: orderId,
        status: OPEN,
        description: description,
        tasks: []
    };

    WorkOrder|error result = libraryClient->/assets/[tag]/workorders.post(workOrder);
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Opened work order '${result.orderId}'.`);
}

# Replaces a work order's description, preserving its existing tasks.
#
# The PUT endpoint replaces the whole work order, so we resend the tasks we
# already have. Omitting them would silently wipe the task list.
#
# + tag - Asset tag owning the work order
# + asset - The asset as already fetched, used to recover the current tasks
function editWorkOrder(string tag, Asset asset) {
    string orderId = io:readln("  Work order ID to edit: ").trim();

    WorkOrder? existing = ();
    foreach WorkOrder w in asset.workOrders {
        if w.orderId == orderId {
            existing = w;
            break;
        }
    }
    if existing is () {
        io:println("  No such work order on this asset.");
        return;
    }

    string description = io:readln("  New description: ").trim();

    WorkOrder updated = {
        orderId: orderId,
        status: existing.status,
        description: description,
        tasks: existing.tasks
    };

    WorkOrder|error result = libraryClient->/assets/[tag]/workorders/[orderId].put(updated);
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Updated work order '${result.orderId}'.`);
}

# Moves a work order to a new state. This is how a job gets closed.
#
# + tag - Asset tag owning the work order
function changeWorkOrderStatus(string tag) {
    string orderId = io:readln("  Work order ID: ").trim();
    string status = io:readln("  New status (OPEN / IN_PROGRESS / CLOSED): ").trim();

    // Validate locally too, so an obvious typo doesn't cost a round trip.
    if status !is WorkOrderStatus {
        io:println("  Invalid status.");
        return;
    }

    WorkOrder|error result =
        libraryClient->/assets/[tag]/workorders/[orderId].patch((), status = status);
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Work order '${result.orderId}' is now ${result.status}.`);
}

# Deletes a work order and every task under it.
#
# + tag - Asset tag owning the work order
function deleteWorkOrder(string tag) {
    string orderId = io:readln("  Work order ID to delete: ").trim();
    WorkOrder|error result = libraryClient->/assets/[tag]/workorders/[orderId].delete();
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Deleted work order '${result.orderId}' and its ${result.tasks.length()} task(s).`);
}

# Adds a sub-task to an existing work order.
#
# + tag - Asset tag owning the work order
function addWorkOrderTask(string tag) {
    string orderId = io:readln("  Work order ID: ").trim();
    string taskId = io:readln("  Task ID: ").trim();
    string description = io:readln("  Task description: ").trim();

    Task task = {taskId: taskId, description: description};

    Task|error result = libraryClient->/assets/[tag]/workorders/[orderId]/tasks.post(task);
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Added task '${result.taskId}'.`);
}

# Removes a sub-task from a work order.
#
# + tag - Asset tag owning the work order
function removeWorkOrderTask(string tag) {
    string orderId = io:readln("  Work order ID: ").trim();
    string taskId = io:readln("  Task ID to remove: ").trim();

    Task|error result =
        libraryClient->/assets/[tag]/workorders/[orderId]/tasks/[taskId].delete();
    if result is error {
        reportError(result);
        return;
    }
    io:println(string `  Removed task '${result.taskId}'.`);
}

// ----------------------------------------------------------------------------
// EXTRA — asset detail lookup
// ----------------------------------------------------------------------------

# Shows one asset in full, including components, schedules, and work orders.
function inspectAsset() {
    header("ASSET DETAIL");
    string tag = io:readln("  Asset tag: ").trim();
    Asset|error asset = libraryClient->/assets/[tag];
    if asset is error {
        reportError(asset);
        return;
    }
    io:println("");
    printAssetDetail(asset);
}

// ----------------------------------------------------------------------------
// MENU LOOP
// ----------------------------------------------------------------------------

public function main() {
    io:println("\n  Ministry of Higher Education - Library & Resource Management");
    io:println("  Connected to http://localhost:9090/library");

    while true {
        io:println("\n  ------------------------------");
        io:println("  1. Loaning & Booking");
        io:println("  2. Global View");
        io:println("  3. Campus View");
        io:println("  4. Overdue Dashboard");
        io:println("  5. Schedule Manager");
        io:println("  6. Work Order Manager");
        io:println("  7. Inspect an asset");
        io:println("  0. Exit");
        string choice = io:readln("  Select: ").trim();

        match choice {
            "1" => {
                loanAndBook();
            }
            "2" => {
                globalView();
            }
            "3" => {
                campusView();
            }
            "4" => {
                overdueDashboard();
            }
            "5" => {
                scheduleManager();
            }
            "6" => {
                workOrderManager();
            }
            "7" => {
                inspectAsset();
            }
            "0" => {
                io:println("  Goodbye.");
                return;
            }
            _ => {
                io:println("  Unknown option.");
            }
        }
    }
}
