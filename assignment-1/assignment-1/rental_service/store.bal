import ballerina/time;


public type CartEntry record {|
    string propertyId;
    string checkIn;
    string checkOut;
    int nights;
|};


# All registered accommodation listings, keyed by property id.
isolated map<Property> propertyTable = {};

# All registered users, hosts and guests alike, keyed by user id.
isolated map<User> userTable = {};

# All confirmed bookings, keyed by booking id. This is what the overlap check
# consults, so only committed reservations belong here.
isolated map<Booking> bookingTable = {};

# Pending requests per guest. Cleared when a booking is confirmed.
isolated map<CartEntry[]> guestCarts = {};

# Monotonic counters behind the generated ids.
isolated int propertyCounter = 0;
isolated int bookingCounter = 0;


isolated function nextPropertyId() returns string {
    lock {
        propertyCounter += 1;
        return string `PROP-${propertyCounter.toString().padZero(3)}`;
    }
}


isolated function nextBookingId() returns string {
    lock {
        bookingCounter += 1;
        return string `BKG-${bookingCounter.toString().padZero(3)}`;
    }
}

public isolated function addProperty(AddPropertyRequest request)
        returns Property|error {
    if request.host_id == "" {
        return error("host_id is required");
    }
    if request.name == "" {
        return error("Property name is required");
    }
    if request.price_per_night <= 0.0 {
        return error("Price per night must be greater than zero");
    }

    string propertyId = nextPropertyId();

    lock {
        AddPropertyRequest r = request.clone();
        Property property = {
            property_id: propertyId,
            host_id: r.host_id,
            name: r.name,
            location: r.location,
            region: r.region,
            property_type: r.property_type,
            price_per_night: r.price_per_night,
            // An unset status defaults to AVAILABLE rather than UNSPECIFIED.
            status: r.status == PROPERTY_STATUS_UNSPECIFIED ? AVAILABLE : r.status,
            description: r.description
        };
        propertyTable[property.property_id] = property;
        return property.clone();
    }
}

# Looks up a property.
#
# + propertyId - The id to look up
# + return - A copy of the property, or `()` if unknown
public isolated function getProperty(string propertyId) returns Property? {
    lock {
        Property? property = propertyTable[propertyId];
        return property.clone();
    }
}

# Applies partial updates to a listing. Empty and zero fields are left alone,
# so a host can change the price without resending the whole listing.
#
# + request - Fields to change, keyed by property id
# + return - A copy of the updated property, or an error if unknown or not owned
public isolated function updateProperty(UpdatePropertyRequest request)
        returns Property|error {
    lock {
        UpdatePropertyRequest r = request.clone();
        Property? existing = propertyTable[r.property_id];
        if existing is () {
            return error(string `Property '${r.property_id}' not found`);
        }
        // A host may only edit their own listing.
        if r.host_id != "" && existing.host_id != r.host_id {
            return error(string `Property '${r.property_id}' belongs to another host`);
        }
        if r.name != "" {
            existing.name = r.name;
        }
        if r.location != "" {
            existing.location = r.location;
        }
        if r.price_per_night > 0.0 {
            existing.price_per_night = r.price_per_night;
        }
        if r.status != PROPERTY_STATUS_UNSPECIFIED {
            existing.status = r.status;
        }
        if r.description != "" {
            existing.description = r.description;
        }
        return existing.clone();
    }
}

# Deletes a listing.
#
# + propertyId - The listing to remove
# + hostId - Owner making the request; blank skips the ownership check
# + return - A copy of the removed property, or an error if unknown or not owned
public isolated function removeProperty(string propertyId, string hostId)
        returns Property|error {
    lock {
        Property? existing = propertyTable[propertyId];
        if existing is () {
            return error(string `Property '${propertyId}' not found`);
        }
        if hostId != "" && existing.host_id != hostId {
            return error(string `Property '${propertyId}' belongs to another host`);
        }
        Property? removed = propertyTable.removeIfHasKey(propertyId);
        if removed is () {
            return error(string `Property '${propertyId}' not found`);
        }
        return removed.clone();
    }
}

# Lists available properties in one region — the response to remove_property.
#
# + region - Region to filter by; blank returns every available property
# + return - Copies of the matching properties
public isolated function availableInRegion(string region) returns Property[] {
    lock {
        Property[] matches = from Property p in propertyTable
            where p.status == AVAILABLE
            where region == "" || p.region == region
            select p;
        return matches.clone();
    }
}

# Lists available properties matching optional location and price filters.
#
# + location - Location to match, or blank for any
# + minPrice - Lower price bound, or zero for no lower bound
# + maxPrice - Upper price bound, or zero for no upper bound
# + return - Copies of the matching properties
public isolated function findAvailableProperties(string location, float minPrice,
        float maxPrice) returns Property[] {
    lock {
        Property[] matches = from Property p in propertyTable
            where p.status == AVAILABLE
            where location == "" || p.location == location
            where minPrice <= 0.0 || p.price_per_night >= minPrice
            where maxPrice <= 0.0 || p.price_per_night <= maxPrice
            select p;
        return matches.clone();
    }
}
# + propertyId - Property to check
# + checkIn - Proposed arrival date
# + checkOut - Proposed departure date
# + return - `true` if no confirmed booking overlaps the range
public isolated function isFreeForDates(string propertyId, string checkIn,
        string checkOut) returns boolean {
    lock {
        Booking[] clashes = from Booking b in bookingTable
            where b.property_id == propertyId
            where datesOverlap(checkIn, checkOut, b.check_in, b.check_out)
            select b;
        return clashes.length() == 0;
    }
}

// ----------------------------------------------------------------------------
// CART
// ----------------------------------------------------------------------------

# Adds a validated request to a guest's cart. Nothing is committed here.
#
# + guestId - Guest making the request
# + entry - The pending request
# + return - The new size of the guest's cart
public isolated function addToCart(string guestId, CartEntry entry) returns int {
    lock {
        CartEntry[] cart = guestCarts.hasKey(guestId)
            ? <CartEntry[]>guestCarts[guestId]
            : [];
        cart.push(entry.clone());
        guestCarts[guestId] = cart;
        return cart.length();
    }
}

# Reads a guest's cart without emptying it.
#
# + guestId - Guest whose cart to read
# + return - Copies of the pending entries
public isolated function getCart(string guestId) returns CartEntry[] {
    lock {
        CartEntry[]? cart = guestCarts[guestId];
        if cart is () {
            return [];
        }
        return cart.clone();
    }
}

# Empties a guest's cart, called once a confirmation completes.
#
# + guestId - Guest whose cart to clear
public isolated function clearCart(string guestId) {
    lock {
        _ = guestCarts.removeIfHasKey(guestId);
    }
}

// ----------------------------------------------------------------------------
// BOOKINGS
// ----------------------------------------------------------------------------

# Commits a booking, re-checking availability inside the same lock.
#
# The check and the write MUST share one lock. Splitting them would let two
# guests both see a free property and both book the same dates.
#
# + propertyId - Property being booked
# + guestId - Guest making the booking
# + checkIn - Arrival date
# + checkOut - Departure date
# + nights - Number of nights
# + pricePerNight - Nightly rate at the time of confirmation
# + return - A copy of the confirmed booking, or an error if the dates clash
public isolated function commitBooking(string propertyId, string guestId,
        string checkIn, string checkOut, int nights, float pricePerNight)
        returns Booking|error {
    string bookingId = nextBookingId();
    lock {
        // Re-check inside the lock, not before it.
        Booking[] clashes = from Booking b in bookingTable
            where b.property_id == propertyId
            where datesOverlap(checkIn, checkOut, b.check_in, b.check_out)
            select b;
        if clashes.length() > 0 {
            return error(string `Property '${propertyId}' is already booked for ${checkIn} to ${checkOut}`);
        }

        Booking booking = {
            booking_id: bookingId,
            property_id: propertyId,
            guest_id: guestId,
            check_in: checkIn,
            check_out: checkOut,
            nights: nights,
            total_cost: pricePerNight * <float>nights
        };
        bookingTable[booking.booking_id] = booking;
        return booking.clone();
    }
}

// ----------------------------------------------------------------------------
// SEED DATA
// ----------------------------------------------------------------------------

# Loads sample hosts, guests, and listings so the client has something to
# work with on a fresh start.
public isolated function seedData() {
    User[] users = [
        {user_id: "H001", name: "Maria Shipanga", email: "maria@host.na", role: HOST, region: "Khomas"},
        {user_id: "H002", name: "Petrus Amupolo", email: "petrus@host.na", role: HOST, region: "Erongo"},
        {user_id: "G001", name: "Anna Nghipandulwa", email: "anna@guest.na", role: GUEST, region: ""}
    ];
    foreach User u in users {
        User|error result = addUser(u);
        if result is error {
            // Already seeded; ignore.
        }
    }

    AddPropertyRequest[] properties = [
        {
            host_id: "H001",
            name: "Windhoek City Apartment",
            location: "Windhoek",
            region: "Khomas",
            property_type: APARTMENT,
            price_per_night: 850.0,
            status: AVAILABLE,
            description: "Two-bedroom apartment near the CBD."
        },
        {
            host_id: "H001",
            name: "Auas Hills Guesthouse",
            location: "Windhoek",
            region: "Khomas",
            property_type: GUESTHOUSE,
            price_per_night: 1200.0,
            status: AVAILABLE,
            description: "Quiet guesthouse with mountain views."
        },
        {
            host_id: "H002",
            name: "Swakopmund Beach House",
            location: "Swakopmund",
            region: "Erongo",
            property_type: HOUSE,
            price_per_night: 1750.0,
            status: AVAILABLE,
            description: "Four sleeper, two minutes from the beach."
        },
        {
            host_id: "H002",
            name: "Desert Lodge Room",
            location: "Walvis Bay",
            region: "Erongo",
            property_type: ROOM,
            price_per_night: 600.0,
            status: MAINTENANCE,
            description: "Single room, currently closed for refurbishment."
        }
    ];
    foreach AddPropertyRequest p in properties {
        Property|error result = addProperty(p);
        if result is error {
            // Already seeded; ignore.
        }
    }
}
