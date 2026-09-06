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
}