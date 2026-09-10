// ============================================================================
// rentalservice_client.bal — gRPC client for the Rental Accommodation System.
//
// Generated skeleton from:
//   bal grpc --mode client --input rental.proto --output rental_client/
// then replaced with a menu-driven client exercising all eight operations,
// including both streaming styles.
//
// Run the server FIRST (bal run in ../rental_service), then run this.
// ============================================================================
import ballerina/io;
import ballerina/time;

final RentalServiceClient ep = check new ("http://localhost:9090");

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

# Prints one property as a summary block.
#
# + p - The property to display
function printProperty(Property p) {
    io:println(string `  ${p.property_id}  ${p.name}`);
    io:println(string `    ${p.property_type} in ${p.location} (${p.region})`);
    io:println(string `    N$${p.price_per_night} per night  [${p.status}]`);
    if p.description != "" {
        io:println(string `    ${p.description}`);
    }
}

# Prints one confirmed booking.
#
# + b - The booking to display
function printBooking(Booking b) {
    io:println(string `  ${b.booking_id}  property ${b.property_id}`);
    io:println(string `    ${b.check_in} to ${b.check_out}  (${b.nights} night(s))`);
    io:println(string `    Total: N$${b.total_cost}`);
}

// ----------------------------------------------------------------------------
// 1. add_property  (simple RPC)
// ----------------------------------------------------------------------------

# Registers a new listing on behalf of a host.
function addPropertyFlow() {
    header("ADD PROPERTY (simple RPC)");

    string hostId = io:readln("  Host ID (e.g. H001): ").trim();
    string name = io:readln("  Property name: ").trim();
    string location = io:readln("  Location (town): ").trim();
    string region = io:readln("  Region: ").trim();
    string typeInput = io:readln("  Type (APARTMENT/HOUSE/GUESTHOUSE/LODGE/ROOM): ").trim();
    string priceInput = io:readln("  Price per night: ").trim();
    string description = io:readln("  Description: ").trim();

    if typeInput !is PropertyType {
        io:println("  Invalid property type.");
        return;
    }
    float|error price = float:fromString(priceInput);
    if price is error {
        io:println("  Price must be a number.");
        return;
    }

    AddPropertyRequest request = {
        host_id: hostId,
        name: name,
        location: location,
        region: region,
        property_type: typeInput,
        price_per_night: price,
        status: AVAILABLE,
        description: description
    };

    AddPropertyResponse|error response = ep->add_property(request);
    if response is error {
        io:println("  RPC failed: " + response.message());
        return;
    }
    io:println("\n  " + response.message);
    if response.success {
        io:println("  New property ID: " + response.property_id);
    }
}

// ----------------------------------------------------------------------------
// 2. update_property  (simple RPC)
// ----------------------------------------------------------------------------

# Updates a listing. Blank answers leave a field unchanged.
function updatePropertyFlow() {
    header("UPDATE PROPERTY (simple RPC)");
    io:println("  Leave a field blank to keep its current value.\n");

    string propertyId = io:readln("  Property ID: ").trim();
    string hostId = io:readln("  Your host ID: ").trim();
    string name = io:readln("  New name: ").trim();
    string location = io:readln("  New location: ").trim();
    string priceInput = io:readln("  New price per night: ").trim();
    string statusInput = io:readln("  New status (AVAILABLE/UNAVAILABLE/MAINTENANCE): ").trim();
    string description = io:readln("  New description: ").trim();

    float price = 0.0;
    if priceInput != "" {
        float|error parsed = float:fromString(priceInput);
        if parsed is error {
            io:println("  Price must be a number.");
            return;
        }
        price = parsed;
    }

    // An unset enum must be UNSPECIFIED, which the server reads as "no change".
    PropertyStatus status = PROPERTY_STATUS_UNSPECIFIED;
    if statusInput != "" {
        if statusInput !is PropertyStatus {
            io:println("  Invalid status.");
            return;
        }
        status = statusInput;
    }

    UpdatePropertyRequest request = {
        property_id: propertyId,
        host_id: hostId,
        name: name,
        location: location,
        price_per_night: price,
        status: status,
        description: description
    };

    UpdatePropertyResponse|error response = ep->update_property(request);
    if response is error {
        io:println("  RPC failed: " + response.message());
        return;
    }
    io:println("\n  " + response.message);
    if response.success {
        printProperty(response.property);
    }
}

// ----------------------------------------------------------------------------
// 3. remove_property  (simple RPC, returns the remaining regional list)
// ----------------------------------------------------------------------------

# Deletes a listing and shows what is left available in that region.
function removePropertyFlow() {
    header("REMOVE PROPERTY (simple RPC)");

    string propertyId = io:readln("  Property ID to remove: ").trim();
    string hostId = io:readln("  Your host ID: ").trim();

    RemovePropertyResponse|error response =
        ep->remove_property({property_id: propertyId, host_id: hostId});
    if response is error {
        io:println("  RPC failed: " + response.message());
        return;
    }

    io:println("\n  " + response.message);
    if !response.success {
        return;
    }

    io:println("\n  Still available in this region:");
    if response.remaining_properties.length() == 0 {
        io:println("    (none)");
        return;
    }
    foreach Property p in response.remaining_properties {
        printProperty(p);
        io:println("");
    }
}

// ----------------------------------------------------------------------------
// 4. create_users  (CLIENT-SIDE STREAMING)
// ----------------------------------------------------------------------------

# Streams several user profiles to the server in one call.
#
# The shape of a client-streaming call: open the stream, send repeatedly,
# `complete()` to signal the end, then receive ONE response. The server does
# not reply until `complete()` arrives.
function createUsersFlow() {
    header("CREATE USERS (client-side streaming)");
    io:println("  Enter users one at a time. Blank user ID finishes the batch.\n");

    User[] batch = [];
    while true {
        string userId = io:readln("  User ID (blank to finish): ").trim();
        if userId == "" {
            break;
        }
        string name = io:readln("    Name: ").trim();
        string email = io:readln("    Email: ").trim();
        string roleInput = io:readln("    Role (HOST/GUEST): ").trim();
        if roleInput !is UserRole {
            io:println("    Invalid role, skipping this user.");
            continue;
        }
        string region = roleInput == HOST ? io:readln("    Region: ").trim() : "";

        batch.push({
            user_id: userId,
            name: name,
            email: email,
            role: roleInput,
            region: region
        });
    }

    if batch.length() == 0 {
        io:println("  Nothing to send.");
        return;
    }

    Create_usersStreamingClient|error streamingClient = ep->create_users();
    if streamingClient is error {
        io:println("  Could not open stream: " + streamingClient.message());
        return;
    }

    io:println(string `${"\n"}  Streaming ${batch.length()} user(s)...`);
    foreach User u in batch {
        error? sent = streamingClient->sendUser(u);
        if sent is error {
            io:println("  Send failed: " + sent.message());
            return;
        }
    }

    // Tells the server no more messages are coming. Without this the server
    // would block on forEach forever.
    error? completed = streamingClient->complete();
    if completed is error {
        io:println("  Complete failed: " + completed.message());
        return;
    }

    CreateUsersResponse|error? response = streamingClient->receiveCreateUsersResponse();
    if response is error {
        io:println("  Receive failed: " + response.message());
        return;
    }
    if response is () {
        io:println("  No response from server.");
        return;
    }

    io:println("\n  " + response.message);
    io:println(string `  Created: ${response.created_count}   Failed: ${response.failed_count}`);
    if response.failed_user_ids.length() > 0 {
        io:println("  Rejected IDs: " + response.failed_user_ids.toString());
    }
}

// ----------------------------------------------------------------------------
// 5. list_available_properties  (SERVER-SIDE STREAMING)
// ----------------------------------------------------------------------------

# Consumes a stream of available listings, optionally filtered.
#
# The call returns a `stream` immediately; results arrive one message at a
# time as the server produces them. `forEach` drains it.
function listAvailableFlow() {
    header("LIST AVAILABLE PROPERTIES (server-side streaming)");
    io:println("  Leave filters blank for no filtering.\n");

    string location = io:readln("  Location: ").trim();
    string minInput = io:readln("  Minimum price: ").trim();
    string maxInput = io:readln("  Maximum price: ").trim();

    float minPrice = 0.0;
    if minInput != "" {
        float|error parsed = float:fromString(minInput);
        if parsed is error {
            io:println("  Minimum price must be a number.");
            return;
        }
        minPrice = parsed;
    }

    float maxPrice = 0.0;
    if maxInput != "" {
        float|error parsed = float:fromString(maxInput);
        if parsed is error {
            io:println("  Maximum price must be a number.");
            return;
        }
        maxPrice = parsed;
    }

    stream<Property, error?>|error propertyStream = ep->list_available_properties({
        location: location,
        min_price: minPrice,
        max_price: maxPrice
    });
    if propertyStream is error {
        io:println("  RPC failed: " + propertyStream.message());
        return;
    }

    io:println("");
    int count = 0;
    error? streamResult = propertyStream.forEach(function(Property p) {
        count += 1;
        printProperty(p);
        io:println("");
    });
    if streamResult is error {
        io:println("  Stream ended with an error: " + streamResult.message());
        return;
    }
    io:println(count == 0 ? "  No matching properties." : string `  ${count} property(ies) streamed.`);
}

// ----------------------------------------------------------------------------
// 6. search_property  (simple RPC)
// ----------------------------------------------------------------------------

# Looks up a single listing by id.
function searchPropertyFlow() {
    header("SEARCH PROPERTY (simple RPC)");

    string propertyId = io:readln("  Property ID: ").trim();

    SearchPropertyResponse|error response = ep->search_property({property_id: propertyId});
    if response is error {
        io:println("  RPC failed: " + response.message());
        return;
    }

    io:println("\n  " + response.status_message);
    if response.property.property_id != "" {
        io:println("");
        printProperty(response.property);
    }
}

// ----------------------------------------------------------------------------
// 7. book_property  (simple RPC, adds to cart)
// ----------------------------------------------------------------------------

# Places a booking request in the guest's cart. Nothing is committed yet.
function bookPropertyFlow() {
    header("BOOK PROPERTY (simple RPC - adds to cart)");

    string guestId = io:readln("  Guest ID (e.g. G001): ").trim();
    string propertyId = io:readln("  Property ID: ").trim();
    string checkIn = io:readln("  Check-in (YYYY-MM-DD): ").trim();
    string checkOut = io:readln("  Check-out (YYYY-MM-DD): ").trim();

    BookPropertyResponse|error response = ep->book_property({
        guest_id: guestId,
        property_id: propertyId,
        check_in: checkIn,
        check_out: checkOut
    });
    if response is error {
        io:println("  RPC failed: " + response.message());
        return;
    }

    io:println("\n  " + response.message);
    if response.success {
        io:println(string `  ${response.nights} night(s), estimated N$${response.estimated_cost}`);
        io:println(string `  Items in cart: ${response.cart_size}`);
        io:println("  Nothing is reserved until you confirm.");
    }
}

// ----------------------------------------------------------------------------
// 8. confirm_booking  (simple RPC, commits the cart)
// ----------------------------------------------------------------------------

# Finalises everything in the guest's cart.
function confirmBookingFlow() {
    header("CONFIRM BOOKING (simple RPC - commits the cart)");

    string guestId = io:readln("  Guest ID: ").trim();

    ConfirmBookingResponse|error response = ep->confirm_booking({guest_id: guestId});
    if response is error {
        io:println("  RPC failed: " + response.message());
        return;
    }

    io:println("\n  " + response.message);

    if response.confirmed_bookings.length() > 0 {
        io:println("\n  Confirmed:");
        foreach Booking b in response.confirmed_bookings {
            printBooking(b);
            io:println("");
        }
        io:println(string `  GRAND TOTAL: N$${response.grand_total}`);
    }

    if response.rejected_reasons.length() > 0 {
        io:println("\n  Rejected:");
        foreach string reason in response.rejected_reasons {
            io:println("    - " + reason);
        }
    }
}

// ----------------------------------------------------------------------------
// DEMO — runs every operation end to end without prompting
// ----------------------------------------------------------------------------

# Exercises all eight RPCs in sequence.
#
# IDEMPOTENT BY DESIGN. The server keeps its state in memory for as long as it
# runs, so a demo that hard-codes ids or dates only works on the first run.
# Instead this creates its own properties, derives unique user ids and booking
# dates from a run number, and cleans up the property it created. Run it as
# many times as you like without restarting the server.
function runDemo() returns error? {
    header("AUTOMATED DEMO - all eight operations");

    // A per-run discriminator, so repeated runs never collide.
    string runId = time:utcNow()[0].toString();
    string tag = runId.substring(runId.length() - 5);
    // Push each run's dates a year apart so bookings never overlap.
    int yearOffset = <int>(time:utcNow()[0] % 50) + 2030;
    string bookIn = string `${yearOffset}-03-01`;
    string bookOut = string `${yearOffset}-03-05`;

    io:println(string `${"\n"}  Run tag: ${tag}   Booking window: ${bookIn} to ${bookOut}`);

    // ---- 1. add_property -------------------------------------------------
    io:println("\n[1] add_property (simple)");
    AddPropertyResponse added = check ep->add_property({
        host_id: "H001",
        name: string `Demo Cottage ${tag}`,
        location: "Windhoek",
        region: "Khomas",
        property_type: HOUSE,
        price_per_night: 700.0,
        status: AVAILABLE,
        description: "Created by the automated demo."
    });
    io:println("  " + added.message + "  -> " + added.property_id);

    // A second listing, so step 8 has something of its own to delete.
    AddPropertyResponse disposable = check ep->add_property({
        host_id: "H001",
        name: string `Demo Flat ${tag}`,
        location: "Windhoek",
        region: "Khomas",
        property_type: APARTMENT,
        price_per_night: 500.0,
        status: AVAILABLE,
        description: "Will be removed at the end of this demo."
    });
    io:println("  " + disposable.message + "  -> " + disposable.property_id);

    // ---- 2. create_users (client streaming) ------------------------------
    io:println("\n[2] create_users (client streaming)");
    Create_usersStreamingClient usersStream = check ep->create_users();
    string guestId = string `G-${tag}-A`;
    User[] newUsers = [
        {user_id: guestId, name: "Tomas Haufiku", email: "tomas@guest.na", role: GUEST, region: ""},
        {user_id: string `G-${tag}-B`, name: "Lena Kaapanda", email: "lena@guest.na", role: GUEST, region: ""},
        // A deliberate duplicate of a seeded user, to show the failure count.
        {user_id: "G001", name: "Duplicate", email: "dup@guest.na", role: GUEST, region: ""}
    ];
    foreach User u in newUsers {
        check usersStream->sendUser(u);
    }
    check usersStream->complete();
    CreateUsersResponse? usersResult = check usersStream->receiveCreateUsersResponse();
    if usersResult is CreateUsersResponse {
        io:println(string `  Created ${usersResult.created_count}, failed ${usersResult.failed_count} ` +
            string `${usersResult.failed_user_ids.toString()}  (the failure is the intentional duplicate)`);
    }

    // ---- 3. update_property ----------------------------------------------
    io:println("\n[3] update_property (simple)");
    UpdatePropertyResponse updated = check ep->update_property({
        property_id: added.property_id,
        host_id: "H001",
        name: "",
        location: "",
        price_per_night: 780.0,
        status: PROPERTY_STATUS_UNSPECIFIED,
        description: ""
    });
    io:println("  " + updated.message + string `  new price N$${updated.property.price_per_night}`);
    io:println("  (name and description untouched - only non-empty fields are applied)");

    // ---- 4. list_available_properties (server streaming) -----------------
    io:println("\n[4] list_available_properties (server streaming)");
    stream<Property, error?> available = check ep->list_available_properties({
        location: "Windhoek",
        min_price: 0.0,
        max_price: 0.0
    });
    int streamed = 0;
    check available.forEach(function(Property p) {
        streamed += 1;
        io:println(string `  ${p.property_id}  ${p.name}  N$${p.price_per_night}`);
    });
    io:println(string `  (${streamed} streamed, filtered to Windhoek)`);

    // ---- 5. search_property ----------------------------------------------
    io:println("\n[5] search_property (simple)");
    SearchPropertyResponse found = check ep->search_property({property_id: added.property_id});
    io:println("  " + found.status_message);
    SearchPropertyResponse missing = check ep->search_property({property_id: "PROP-NONE"});
    io:println("  " + missing.status_message);
    // PROP-004 is seeded in MAINTENANCE, so it exists but is not bookable.
    SearchPropertyResponse notBookable = check ep->search_property({property_id: "PROP-004"});
    io:println("  " + notBookable.status_message);

    // ---- 6. book_property -------------------------------------------------
    io:println("\n[6] book_property (simple, into cart)");
    BookPropertyResponse booked1 = check ep->book_property({
        guest_id: guestId,
        property_id: added.property_id,
        check_in: bookIn,
        check_out: bookOut
    });
    io:println(string `  ${booked1.message} (${booked1.nights} nights, est N$${booked1.estimated_cost})`);

    BookPropertyResponse booked2 = check ep->book_property({
        guest_id: guestId,
        property_id: disposable.property_id,
        check_in: bookIn,
        check_out: bookOut
    });
    io:println(string `  ${booked2.message} (cart size ${booked2.cart_size})`);

    // Invalid range, to show validation rejecting it before it reaches the cart.
    BookPropertyResponse badDates = check ep->book_property({
        guest_id: guestId,
        property_id: added.property_id,
        check_in: string `${yearOffset}-11-10`,
        check_out: string `${yearOffset}-11-08`
    });
    io:println("  Invalid range rejected: " + badDates.message);

    // ---- 7. confirm_booking -----------------------------------------------
    io:println("\n[7] confirm_booking (simple, commits cart)");
    ConfirmBookingResponse confirmed = check ep->confirm_booking({guest_id: guestId});
    io:println("  " + confirmed.message);
    foreach Booking b in confirmed.confirmed_bookings {
        io:println(string `    ${b.booking_id}  ${b.check_in}->${b.check_out}  ` +
            string `${b.nights} nights  N$${b.total_cost}`);
    }
    io:println(string `  Grand total: N$${confirmed.grand_total}`);

    // ---- 7b. overlap protection -------------------------------------------
    io:println("\n[7b] overlapping dates must now be refused");
    BookPropertyResponse clash = check ep->book_property({
        guest_id: guestId,
        property_id: added.property_id,
        check_in: string `${yearOffset}-03-02`,
        check_out: string `${yearOffset}-03-04`
    });
    io:println("  " + clash.message);

    io:println("\n[7c] but a back-to-back stay starting on the check-out date is fine");
    BookPropertyResponse adjacent = check ep->book_property({
        guest_id: guestId,
        property_id: added.property_id,
        check_in: bookOut,
        check_out: string `${yearOffset}-03-08`
    });
    io:println("  " + adjacent.message);
    // Clear the cart again so repeated runs start clean.
    ConfirmBookingResponse _ = check ep->confirm_booking({guest_id: guestId});

    // ---- 8. remove_property -----------------------------------------------
    io:println("\n[8] remove_property (simple, returns regional list)");
    RemovePropertyResponse removed = check ep->remove_property({
        property_id: disposable.property_id,
        host_id: "H001"
    });
    io:println("  " + removed.message);
    io:println(string `  ${removed.remaining_properties.length()} still available in Khomas:`);
    foreach Property p in removed.remaining_properties {
        io:println(string `    ${p.property_id}  ${p.name}`);
    }

    io:println("\n" + DIVIDER);
    io:println("  Demo complete. Safe to run again without restarting the server.");
    io:println(DIVIDER);
}

// ----------------------------------------------------------------------------
// MENU
// ----------------------------------------------------------------------------

public function main() returns error? {
    io:println("\n  Ministry of Tourism - Rental Accommodation System");
    io:println("  gRPC client connected to localhost:9090");

    while true {
        io:println("\n  ------------------------------");
        io:println("  HOST");
        io:println("   1. Add a property");
        io:println("   2. Update a property");
        io:println("   3. Remove a property");
        io:println("   4. Create users        (client streaming)");
        io:println("  GUEST");
        io:println("   5. List available      (server streaming)");
        io:println("   6. Search a property");
        io:println("   7. Book a property     (adds to cart)");
        io:println("   8. Confirm booking     (commits cart)");
        io:println("  ");
        io:println("   9. Run automated demo of all eight");
        io:println("   0. Exit");
        string choice = io:readln("  Select: ").trim();

        match choice {
            "1" => {
                addPropertyFlow();
            }
            "2" => {
                updatePropertyFlow();
            }
            "3" => {
                removePropertyFlow();
            }
            "4" => {
                createUsersFlow();
            }
            "5" => {
                listAvailableFlow();
            }
            "6" => {
                searchPropertyFlow();
            }
            "7" => {
                bookPropertyFlow();
            }
            "8" => {
                confirmBookingFlow();
            }
            "9" => {
                check runDemo();
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
