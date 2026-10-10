import XCTest
import SQLite3
@testable import EEGCore

final class ReferenceLocalProfileStoreTests: XCTestCase {
    typealias Store = ReferenceLocalProfileStore
    let key = Data(repeating: 42,count: 32)
    enum Injected: Error { case interruption }
    func fixture() throws -> ReferenceProfileCodec.Classifier {
        let classes: [ReferenceSignatureTraining.ClassAlgebra] = [Int32(0),1].map { id in
            .init(classReferenceID: id,distributions: [.init(counts: [20,20],mean: id == 0 ? [0,0] : [2,4],covariance: [[1,0],[0,1]],updateTime: 0)])
        }
        let signature = try ReferenceClassifierRebuild.fit(classes,featureChannelMetadata: [[0,0],[1,0]],maximumClasses: 4,maximumCanonicalDiagonalAdditions: 3)
        return try ReferenceRuntimeProfile.classifier(signature,numOfValidFeatures: signature.pca.basis[0].count,useCount: 3)
    }
    func location() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700])
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("profiles.sqlite")
    }
    let settings = Store.Settings(classPriors: [0.4,0.6],neutralScale: 1.5)
    func save(_ store: Store, revision: Int64 = 0, name: String = "first", fault: ((Store.WriteStage) throws -> Void)? = nil) throws -> Int64 {
        try store.save(id: "trial",metadata: ["uuid": .string("trial"),"name": .string(name),
            "ownerId": .string("local-research"),"deleted": .bool(false),"loaded": .bool(true),
            "originalUuid": .string("source"),"originalProfileURL": .string("local:trial"),
            "createdDatetime": .string("2026-10-11T00:00:00Z"),"modifiedDatetime": .string("2026-10-11T00:01:00Z"),
            "eegChannels": .array([.string("AF3"),.string("O1")]),"independentProvenance": .string("synthetic-fit")],classifier: fixture(),settings: settings,expectedRevision: revision,fault: fault)
    }
    func testFitPersistRestartAndScoreWithoutVendorAssets() throws {
        let url = try location(), profile = try fixture()
        let before = try ReferenceRuntimeProfile.runtime(profile,classPriors: settings.classPriors,neutralScale: settings.neutralScale)
        let store = try Store(url: url,key: key)
        XCTAssertEqual(try save(store),1); try store.close()
        let reopened = try Store(url: url,key: key)
        let record = try XCTUnwrap(reopened.load(id: "trial"))
        XCTAssertEqual(record.classifier,profile); XCTAssertEqual(record.revision,1)
        XCTAssertEqual(record.metadata["eegChannels"],.array([.string("AF3"),.string("O1")]))
        XCTAssertEqual(record.metadata["independentProvenance"],.string("synthetic-fit"))
        XCTAssertEqual(record.metadata["createdDatetime"],.string("2026-10-11T00:00:00Z"))
        for input in [[0.0,0],[1,2],[2,4]] {
            let a = try ReferenceRuntimeProfile.infer(featureVector: input,runtime: before)
            let b = try ReferenceRuntimeProfile.infer(featureVector: input,runtime: record.runtime)
            XCTAssertEqual(a.posterior,b.posterior); XCTAssertEqual(a.classDensity,b.classDensity)
        }
        XCTAssertThrowsError(try save(reopened)) { XCTAssertEqual($0 as? Store.Failure,.conflict) }
        let competing = try Store(url: url,key: key)
        XCTAssertEqual(try save(competing,revision: 1),2)
        XCTAssertThrowsError(try save(reopened,revision: 1)) { XCTAssertEqual($0 as? Store.Failure,.conflict) }
    }
    func testBeforeCommitRollbackAndAfterCommitAcknowledgementAreDistinct() throws {
        let url = try location(), store = try Store(url: url,key: key)
        _ = try save(store)
        XCTAssertThrowsError(try save(store,revision: 1,name: "interrupted") { stage in
            if case .beforeCommit = stage { throw Injected.interruption }
        })
        XCTAssertEqual(try store.load(id: "trial")?.metadata["name"],.string("first"))
        XCTAssertThrowsError(try save(store,revision: 1,name: "committed") { stage in
            if case .afterCommit = stage { throw Injected.interruption }
        }) { XCTAssertEqual($0 as? Store.Failure,.committedWithoutAcknowledgement(2)) }
        try store.close()
        let reopened = try Store(url: url,key: key)
        XCTAssertEqual(try reopened.load(id: "trial")?.metadata["name"],.string("committed"))
        XCTAssertEqual(try reopened.load(id: "trial")?.revision,2)
    }
    func testWrongKeyAndTamperFailClosed() throws {
        let url = try location(), store = try Store(url: url,key: key)
        _ = try save(store); try store.close()
        let wrong = try Store(url: url,key: Data(repeating: 99,count: 32))
        XCTAssertThrowsError(try wrong.load(id: "trial")) { XCTAssertEqual($0 as? Store.Failure,.corrupt) }
        try wrong.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path,&database),SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database,"UPDATE profiles SET revision=9",nil,nil,nil),SQLITE_OK)
        sqlite3_close(database)
        let reopened = try Store(url: url,key: key)
        XCTAssertThrowsError(try reopened.load(id: "trial")) { XCTAssertEqual($0 as? Store.Failure,.corrupt) }
    }
    func testInvalidIdentityAndClosedStoreDoNotWrite() throws {
        let url = try location(), store = try Store(url: url,key: key)
        XCTAssertThrowsError(try store.save(id: "trial",metadata: ["uuid": .string("other")],classifier: fixture(),settings: settings,expectedRevision: 0))
        XCTAssertNil(try store.load(id: "trial"))
        XCTAssertThrowsError(try store.load(id: "../trial"))
        try store.close()
        XCTAssertThrowsError(try store.load(id: "trial")) { XCTAssertEqual($0 as? Store.Failure,.closed) }
    }
    func testResourceBoundSchemaAndSymlinkReject() throws {
        let url = try location()
        let bounded = try Store(url: url,key: key,maximumBytes: 64)
        XCTAssertThrowsError(try save(bounded))
        XCTAssertNil(try bounded.load(id: "trial")); try bounded.close()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path,&database),SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(database,"PRAGMA user_version=99",nil,nil,nil),SQLITE_OK)
        sqlite3_close(database)
        XCTAssertThrowsError(try Store(url: url,key: key)) { XCTAssertEqual($0 as? Store.Failure,.incompatibleSchema) }
        let link = url.deletingLastPathComponent().appendingPathComponent("alias.sqlite")
        try FileManager.default.createSymbolicLink(at: link,withDestinationURL: url)
        XCTAssertThrowsError(try Store(url: link,key: key))
    }
    func testActualDatabaseLockFailurePreservesPreviousRecord() throws {
        let url = try location(), store = try Store(url: url,key: key,busyTimeoutMilliseconds: 1)
        _ = try save(store)
        var other: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path,&other),SQLITE_OK)
        defer { sqlite3_exec(other,"ROLLBACK",nil,nil,nil); sqlite3_close(other) }
        XCTAssertEqual(sqlite3_exec(other,"BEGIN IMMEDIATE",nil,nil,nil),SQLITE_OK)
        XCTAssertThrowsError(try save(store,revision: 1)) { XCTAssertEqual($0 as? Store.Failure,.database(SQLITE_BUSY)) }
        XCTAssertEqual(try store.load(id: "trial")?.revision,1)
    }
    #if os(macOS)
    func testKilledSQLiteWriterRecoversPreviousCompleteProfile() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sqlite3") else { throw XCTSkip("SQLite CLI unavailable") }
        let url = try location(), store = try Store(url: url,key: key)
        _ = try save(store); try store.close()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [url.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = output
        let staged = expectation(description: "child staged uncommitted write")
        output.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if String(decoding: bytes,as: UTF8.self).contains("STAGED") { staged.fulfill() }
        }
        defer {
            output.fileHandleForReading.readabilityHandler = nil
            if process.isRunning { kill(process.processIdentifier,SIGKILL) }
            input.fileHandleForWriting.closeFile()
        }
        try process.run()
        input.fileHandleForWriting.write(Data("BEGIN IMMEDIATE;\nUPDATE profiles SET revision=2,payload=x'00' WHERE id='trial';\n.print STAGED\n".utf8))
        wait(for: [staged],timeout: 10)
        kill(process.processIdentifier,SIGKILL); process.waitUntilExit()
        let reopened = try Store(url: url,key: key)
        let record = try XCTUnwrap(reopened.load(id: "trial"))
        XCTAssertEqual(record.revision,1); XCTAssertEqual(record.metadata["name"],.string("first"))
        XCTAssertEqual(record.classifier,try fixture())
        _ = try ReferenceRuntimeProfile.infer(featureVector: [1,2],runtime: record.runtime)
    }
    #endif
}
