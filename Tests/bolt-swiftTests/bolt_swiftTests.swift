import XCTest
import packstream_swift

@testable import bolt_swift

class bolt_swiftTests: XCTestCase {
    func testConnection() throws {
        let connectionExp = expectation(description: "Login successful")
        
        let settings = ConnectionSettings(username: "neo4j", password: "<passcode>", userAgent: "Bah")
        let conn = SwiftSocketConnection(hostname: "localhost", settings: settings)
        try conn.connect { (success) in
            do {
                if success == true {
                    connectionExp.fulfill()
                    let _ = try self.createNode(connection: conn)
                }
            } catch {
                // poop
            }
        }
    
        self.waitForExpectations(timeout: 300000) { (error) in
            print("Done")
        }

    }
    
    func createNode(connection conn: SwiftSocketConnection) throws -> XCTestExpectation {
    
        let cypherExp = expectation(description: "Perform cypher query")
        
        let statement = "CREATE (n:FirstNode {name:{name}}) RETURN n"
        let parameters = Map(dictionary: [ "name": "Steven" ])
        let request = Request.run(statement: statement, parameters: parameters)
        try conn.request(request) { (success, response) in
            do {
                if success {
                    cypherExp.fulfill()
                    let _ = try self.pullResults(connection: conn)
                }
            } catch {
                // poop
            }
        }
        
        return cypherExp
    }
    
    func pullResults(connection conn: SwiftSocketConnection) throws -> XCTestExpectation {
        
        let pullAllExp = expectation(description: "Perform pull All")
        
        let request = Request.pullAll()
        print("pull all")
        try conn.request(request) { (success, response) in
            print("got result \(success)")
            if response != nil && success == true {
                pullAllExp.fulfill()
            }
        }
        
        return pullAllExp
    }


    static var allTests : [(String, (bolt_swiftTests) -> () throws -> Void)] {
        return [
            ("testExample", testConnection),
        ]
    }
    
    func testUnpackInitResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa1, 0x86, 0x73, 0x65, 0x72, 0x76, 0x65, 0x72, 0x8b, 0x4e, 0x65, 0x6f, 0x34, 0x6a, 0x2f, 0x33, 0x2e, 0x31, 0x2e, 0x31]
        let response = try Response.unpack(bytes)
        
        // Expected: SUCCESS
        // server: Neo4j/3.1.1
        
        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)
        guard let properties = response.items[0] as? Map else {
                XCTFail("Response metadata should be a Map")
                return
        }
        
        XCTAssertEqual(1, properties.dictionary.count)
        XCTAssertEqual("Neo4j/3.1.1", properties.dictionary["server"] as! String)
    }
    
    func testUnpackEmptyRequestResponse() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0xd0, 0x16, 0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72, 0x1, 0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73, 0x90]
        let response = try Response.unpack(bytes)

        XCTAssertEqual(response.category, .success)

        // Expected: SUCCESS
        // result_available_after: 1 (ms)
        // fields: [] (empty List)
        
        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)
        guard let properties = response.items[0] as? Map,
            let fields = properties.dictionary["fields"] as? List else {
                XCTFail("Response metadata should be a Map")
                return
        }
        
        XCTAssertEqual(0, fields.items.count)
        XCTAssertEqual(1, properties.dictionary["result_available_after"]?.asUInt64())

        
    }
    
    func testUnpackRequestResponseWithNode() throws {
        let bytes: [Byte] = [0xb1, 0x70, 0xa2, 0xd0, 0x16, 0x72, 0x65, 0x73, 0x75, 0x6c, 0x74, 0x5f, 0x61, 0x76, 0x61, 0x69, 0x6c, 0x61, 0x62, 0x6c, 0x65, 0x5f, 0x61, 0x66, 0x74, 0x65, 0x72, 0x2, 0x86, 0x66, 0x69, 0x65, 0x6c, 0x64, 0x73, 0x91, 0x81, 0x6e]
        let response = try Response.unpack(bytes)

        // Expected: SUCCESS
        // result_available_after: 2 (ms)
        // fields: ["n"]
        
        XCTAssertEqual(response.category, .success)
        XCTAssertEqual(1, response.items.count)
        guard let properties = response.items[0] as? Map,
              let fields = properties.dictionary["fields"] as? List else {
            XCTFail("Response metadata should be a Map")
            return
        }
        
        XCTAssertEqual(1, fields.items.count)
        XCTAssertEqual("n", fields.items[0] as! String)
        XCTAssertEqual(2, properties.dictionary["result_available_after"]?.asUInt64())

    }
    
    func testUnpackPullAllRequestAfterCypherRequest() throws {
        let bytes: [Byte] = [0xb1, 0x71, 0x91, 0xb3, 0x4e, 0x12, 0x91, 0x89, 0x46, 0x69, 0x72, 0x73, 0x74, 0x4e, 0x6f, 0x64, 0x65, 0xa1, 0x84, 0x6e, 0x61, 0x6d, 0x65, 0x86, 0x53, 0x74, 0x65, 0x76, 0x65, 0x6e]
        let response = try Response.unpack(bytes)
        
        // Expected: Record with one Node (ID 18)
        // label: FirstNode
        // props: "name" = "Steven"
        
        XCTAssertEqual(response.category, .record)
        guard let node = response.asNode() else {
            XCTFail("Expected response to be a node")
            return
        }
        
        XCTAssertEqual(18, node.id)
        XCTAssertEqual(1, node.labels.count)
        XCTAssertEqual("FirstNode", node.labels[0])
        XCTAssertEqual(1, node.properties.count)
        let (propertyKey, propertyValue) = node.properties.first!
        XCTAssertEqual("name", propertyKey)
        XCTAssertEqual("Steven", propertyValue as! String)
    }
}
