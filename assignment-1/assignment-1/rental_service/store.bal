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