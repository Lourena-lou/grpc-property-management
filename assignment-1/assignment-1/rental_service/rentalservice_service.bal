// ============================================================================
// rentalservice_service.bal — gRPC server implementation.
//
// Generated from rental.proto by:
//   bal grpc --mode service --input rental.proto --output rental_service/
//
// The service declaration, the @grpc:Descriptor annotation, and the remote
// function signatures come from the generator and must match the contract.
// Everything inside the function bodies is ours.
//
// Business logic lives in store.bal; this file translates between the wire
// contract and that logic.
// ============================================================================
import ballerina/grpc;
import ballerina/log;

listener grpc:Listener ep = new (9090);

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on ep {

    # Loads the sample data once when the listener starts.
    function init() {
        seedData();
        log:printInfo("Rental service started on port 9090 with seed data loaded");
    }

    // ------------------------------------------------------------------
    // HOST OPERATIONS
    // ------------------------------------------------------------------

    # Registers a new accommodation listing and returns its generated id.
    #
    # + value - The listing details
    # + return - The new property id, or a failure message
    remote function add_property(AddPropertyRequest value)
            returns AddPropertyResponse|error {
        Property|error created = addProperty(value);
        if created is error {
            return {
                property_id: "",
                success: false,
                message: created.message()
            };
        }
        log:printInfo("Property registered: " + created.property_id);
        return {
            property_id: created.property_id,
            success: true,
            message: string `Property '${created.name}' registered successfully`
        };
    }

    # Updates a listing. Only the fields actually supplied are changed.
    #
    # + value - Fields to change, keyed by property id
    # + return - The updated listing, or a failure message
    remote function update_property(UpdatePropertyRequest value)
            returns UpdatePropertyResponse|error {
        Property|error updated = updateProperty(value);
        if updated is error {
            return {
                success: false,
                message: updated.message(),
                property: {}
            };
        }
        return {
            success: true,
            message: string `Property '${updated.property_id}' updated`,
            property: updated
        };
    }

    # Deletes a listing and returns what remains available in that region.
    #
    # The region is read from the property BEFORE deletion — afterwards it is
    # gone, and we would have nothing to scope the response by.
    #
    # + value - Property and host ids
    # + return - The remaining available listings in the host's region
    remote function remove_property(RemovePropertyRequest value)
            returns RemovePropertyResponse|error {
        Property? target = getProperty(value.property_id);
        string region = target is Property ? target.region : "";

        Property|error removed = removeProperty(value.property_id, value.host_id);
        if removed is error {
            return {
                success: false,
                message: removed.message(),
                remaining_properties: []
            };
        }
        return {
            success: true,
            message: string `Property '${removed.property_id}' removed`,
            remaining_properties: availableInRegion(region)
        };
    }

    # CLIENT-SIDE STREAMING: consumes a stream of user profiles and replies
    # once, after the client signals completion.
    #
    # `clientStream.forEach` blocks until the client calls `complete()`. Only
    # then does the single response go back.
    #
    # + clientStream - Stream of user profiles sent by the client
    # + return - Counts of created and failed registrations
    remote function create_users(stream<User, grpc:Error?> clientStream)
            returns CreateUsersResponse|error {
        int created = 0;
        string[] failed = [];

        check clientStream.forEach(function(User user) {
            User|error result = addUser(user);
            if result is error {
                failed.push(user.user_id == "" ? "(missing id)" : user.user_id);
            } else {
                created += 1;
            }
        });

        log:printInfo(string `create_users: ${created} created, ${failed.length()} failed`);

        return {
            created_count: created,
            failed_count: failed.length(),
            success: failed.length() == 0,
            message: failed.length() == 0
                ? string `All ${created} user(s) registered successfully`
                : string `${created} created, ${failed.length()} rejected`,
            failed_user_ids: failed
        };
    }

    // ------------------------------------------------------------------
    // GUEST OPERATIONS
    // ------------------------------------------------------------------

    # SERVER-SIDE STREAMING: streams matching listings back one at a time.
    #
    # Returning `arr.toStream()` is the direct-return form. The runtime walks
    # the stream and emits each element as a separate message on the wire, so
    # the client can start rendering before the last result is computed.
    #
    # + value - Optional location and price filters
    # + return - A stream of matching properties
    remote function list_available_properties(ListAvailableRequest value)
            returns stream<Property, error?>|error {
        Property[] matches = findAvailableProperties(
            value.location, value.min_price, value.max_price);
        log:printInfo(string `Streaming ${matches.length()} available properties`);
        return matches.toStream();
    }

    # Looks up one listing.
    #
    # A missing or unavailable property is an expected outcome, not a fault, so
    # it comes back as `available: false` rather than a gRPC error status.
    #
    # + value - The property id to look up
    # + return - The listing, or a "Not Available" response
    remote function search_property(SearchPropertyRequest value)
            returns SearchPropertyResponse|error {
        Property? property = getProperty(value.property_id);
        if property is () {
            return {
                available: false,
                status_message: string `Not Available: no property with id '${value.property_id}'`,
                property: {}
            };
        }
        if property.status != AVAILABLE {
            return {
                available: false,
                status_message: string `Not Available: '${property.name}' is currently ${property.status}`,
                property: property
            };
        }
        return {
            available: true,
            status_message: "Available",
            property: property
        };
    }

    # Validates dates and places a request in the guest's temporary cart.
    #
    # Deliberately does NOT commit. The cost returned here is an estimate; the
    # binding figure is computed by confirm_booking.
    #
    # + value - Guest, property, and requested dates
    # + return - An estimate and the new cart size, or a validation failure
    remote function book_property(BookPropertyRequest value)
            returns BookPropertyResponse|error {
        if value.guest_id == "" {
            return {
                success: false,
                message: "guest_id is required",
                nights: 0,
                estimated_cost: 0.0,
                cart_size: 0
            };
        }

        Property? property = getProperty(value.property_id);
        if property is () {
            return {
                success: false,
                message: string `Property '${value.property_id}' not found`,
                nights: 0,
                estimated_cost: 0.0,
                cart_size: getCart(value.guest_id).length()
            };
        }
        if property.status != AVAILABLE {
            return {
                success: false,
                message: string `Property '${property.name}' is ${property.status}`,
                nights: 0,
                estimated_cost: 0.0,
                cart_size: getCart(value.guest_id).length()
            };
        }

        int|error nights = validateDates(value.check_in, value.check_out);
        if nights is error {
            return {
                success: false,
                message: nights.message(),
                nights: 0,
                estimated_cost: 0.0,
                cart_size: getCart(value.guest_id).length()
            };
        }

        // An early clash check, purely so the guest gets feedback now rather
        // than at confirmation. It is NOT authoritative — confirm_booking
        // re-checks under lock, because another guest may book in between.
        if !isFreeForDates(value.property_id, value.check_in, value.check_out) {
            return {
                success: false,
                message: string `'${property.name}' is already booked for those dates`,
                nights: nights,
                estimated_cost: 0.0,
                cart_size: getCart(value.guest_id).length()
            };
        }

        int cartSize = addToCart(value.guest_id, {
            propertyId: value.property_id,
            checkIn: value.check_in,
            checkOut: value.check_out,
            nights: nights
        });

        return {
            success: true,
            message: string `'${property.name}' added to cart. Confirm to finalise.`,
            nights: nights,
            estimated_cost: property.price_per_night * <float>nights,
            cart_size: cartSize
        };
    }

    # Finalises every request in the guest's cart.
    #
    # For each entry: re-check overlap under lock, compute cost as
    # price per night x nights, and record the booking. Entries that now clash
    # are reported rather than silently dropped. The cart is cleared either way,
    # matching the brief's "clear the Guest's temporary request".
    #
    # + value - The guest whose cart to confirm
    # + return - Confirmed bookings, rejections, and the grand total
    remote function confirm_booking(ConfirmBookingRequest value)
            returns ConfirmBookingResponse|error {
        CartEntry[] cart = getCart(value.guest_id);

        if cart.length() == 0 {
            return {
                success: false,
                message: "Your cart is empty. Use book_property first.",
                confirmed_bookings: [],
                rejected_reasons: [],
                grand_total: 0.0
            };
        }

        Booking[] confirmed = [];
        string[] rejected = [];
        float grandTotal = 0.0;

        foreach CartEntry entry in cart {
            Property? property = getProperty(entry.propertyId);
            if property is () {
                rejected.push(string `${entry.propertyId}: listing no longer exists`);
                continue;
            }
            if property.status != AVAILABLE {
                rejected.push(string `${property.name}: now ${property.status}`);
                continue;
            }

            // commitBooking re-checks and writes inside ONE lock.
            Booking|error booking = commitBooking(
                entry.propertyId, value.guest_id, entry.checkIn, entry.checkOut,
                entry.nights, property.price_per_night);

            if booking is error {
                rejected.push(string `${property.name}: ${booking.message()}`);
                continue;
            }

            confirmed.push(booking);
            grandTotal += booking.total_cost;
        }

        clearCart(value.guest_id);

        log:printInfo(string `confirm_booking for ${value.guest_id}: ` +
            string `${confirmed.length()} confirmed, ${rejected.length()} rejected`);

        return {
            success: confirmed.length() > 0,
            message: confirmed.length() == 0
                ? "No bookings could be confirmed"
                : string `${confirmed.length()} booking(s) confirmed`,
            confirmed_bookings: confirmed,
            rejected_reasons: rejected,
            grand_total: grandTotal
        };
    }
}
