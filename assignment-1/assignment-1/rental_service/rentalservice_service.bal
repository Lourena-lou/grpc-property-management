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

    function init() {
        seedData();
        log:printInfo("Rental service started on port 9090 with seed data loaded");
    }

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
}

