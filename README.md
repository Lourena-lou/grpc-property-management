Project Overview

This project was developed for the **DSA612S — Distributed Systems and Applications** course.

It consists of two independent distributed systems developed using **Ballerina**:

1. **Library & Resource Management System** — REST API
2. **Rental Accommodation System** — gRPC

 Technologies:

* Ballerina
* REST / HTTP
* JSON
* gRPC
* Protocol Buffers
* Git & GitHub



 Question 1 — Library & Resource Management System

A REST-based system for managing library and institutional resources.

# Main Features

* Create, view, update and delete assets
* Search and filter assets
* Manage components
* Manage servicing schedules
* Manage work orders and tasks
* Track overdue schedules
* Loan and return assets
* CLI client for interacting with the REST service

# Architecture

```text
library_client
      |
      | HTTP / REST
      ↓
library_service
      |
      ↓
In-Memory Store


The system uses an in-memory data store, so data is reset when the service stops.


# Question 2 Rental Accommodation System

A gRPC-based accommodation system with two main roles:

* **Host** — manages properties
* **Guest** — searches and books properties

# Main Features

* Add and update properties
* Create users
* Remove properties
* Search properties
* List available properties
* Add properties to a booking cart
* Confirm bookings
* Validate date availability
* Calculate booking costs

The system demonstrates:

* Simple RPC
* Client-side streaming
* Server-side streaming

---

# Project Structure

```text
DSA612S/
│
├── library_service/
├── library_client/
│
├── rental_service/
├── rental_client/
│
├── proto/
│
└── README.md


 How to Run

 Library Service


cd library_service
bal run


 Library Client

In another terminal:


cd library_client
bal run

Rental System

Run the gRPC server and client from their respective directories:


bal run


