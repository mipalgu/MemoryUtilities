// MemoryManagerTests.swift
// MemoryUtilities
// 
// Created by Morgan McColl.
// Copyright © 2023 Morgan McColl. All rights reserved.
// 
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions
// are met:
// 
// 1. Redistributions of source code must retain the above copyright
//    notice, this list of conditions and the following disclaimer.
// 
// 2. Redistributions in binary form must reproduce the above
//    copyright notice, this list of conditions and the following
//    disclaimer in the documentation and/or other materials
//    provided with the distribution.
// 
// 3. All advertising materials mentioning features or use of this
//    software must display the following acknowledgement:
// 
//    This product includes software developed by Morgan McColl.
// 
// 4. Neither the name of the author nor the names of contributors
//    may be used to endorse or promote products derived from this
//    software without specific prior written permission.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
// OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
// EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
// PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
// 
// -----------------------------------------------------------------------
// This program is free software; you can redistribute it and/or
// modify it under the above terms or under the terms of the GNU
// General Public License as published by the Free Software Foundation;
// either version 2 of the License, or (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program; if not, see http://www.gnu.org/licenses/
// or write to the Free Software Foundation, Inc., 51 Franklin Street,
// Fifth Floor, Boston, MA  02110-1301, USA.
// 

@testable import MemoryUtilities
import XCTest

/// Test class for ``MemoryManager``.
final class MemoryManagerTests: XCTestCase {

    let packageRootPath = URL(fileURLWithPath: #file)
        .pathComponents.prefix { $0 != "Tests" }.joined(separator: "/").dropFirst()

    var dataStore: URL {
        URL(fileURLWithPath: packageRootPath + "/Tests/MemoryUtilitiesTests/storage/data", isDirectory: false)
    }

    let fileManager = FileManager()

    var manager: MemoryManager!

    let raw: [UInt32] = [0, 0xDEADBEEF, 0, 0, 0, 0, 0, 0, 0]

    override func setUp() {
        _ = raw.withUnsafeBytes {
            fileManager.createFile(atPath: dataStore.path, contents: Data($0))
        }
        manager = MemoryManager(location: dataStore, baseAddress: 0, size: 32)
        XCTAssertNotNil(manager, "Error number: \(errno), page size: \(sysconf(Int32(_SC_PAGESIZE)))")
    }

    override func tearDown() {
        manager = nil
        _ = try? fileManager.removeItem(at: dataStore)
    }

    /// Test init sets stored properties correctly.
    func testMMap() {
        XCTAssertNotEqual(manager.fileDescriptor, 0)
        XCTAssertEqual(manager.baseAddress, 0)
        XCTAssertEqual(manager.size, 32)
        XCTAssertEqual(manager.memory.pointee, 0)
        XCTAssertEqual(manager.memory.advanced(by: 1).pointee, 0xDEADBEEF)
    }

    /// Test init fails for invalid parameters.
    func testInvalidInit() {
        XCTAssertNil(
            MemoryManager(location: dataStore.appendingPathComponent("1234abcd"), baseAddress: 0, size: 8)
        )
        XCTAssertNil(MemoryManager(location: dataStore, baseAddress: -1, size: 8))
        XCTAssertNil(MemoryManager(location: dataStore, baseAddress: 0, size: 0))
        XCTAssertNil(MemoryManager(location: dataStore, baseAddress: 0, size: 3))
        XCTAssertNil(MemoryManager(location: dataStore, baseAddress: 1, size: 4))
        XCTAssertNil(MemoryManager(location: dataStore, baseAddress: 4, size: 4))
    }

    /// Test read returns correct data.
    func testRead() {
        XCTAssertEqual(manager.read(address: 4), 0xDEADBEEF)
        XCTAssertEqual(manager.read(address: 8), 0)
        XCTAssertEqual(manager.read(address: 24), 0)
        XCTAssertNil(manager.read(address: 25))
        XCTAssertNil(manager.read(address: 26))
        XCTAssertNil(manager.read(address: 27))
        XCTAssertEqual(manager.read(address: 28), 0)
        XCTAssertNil(manager.read(address: 29))
        XCTAssertNil(manager.read(address: 33))
        XCTAssertNil(manager.read(address: 31))
        XCTAssertNil(manager.read(address: 36))
        manager.memory[2] = 0xFEEDBEEF
        XCTAssertEqual(manager.read(address: 8), 0xFEEDBEEF)
    }

    /// Test multiple read returns correct data.
    func testMultiRead() {
        XCTAssertEqual(manager.read(address: 4, items: 2), [0xDEADBEEF, 0])
        manager.memory[2] = 0xFEEDBEEF
        XCTAssertEqual(manager.read(address: 4, items: 2), [0xDEADBEEF, 0xFEEDBEEF])
        XCTAssertNil(manager.read(address: 9, items: 2))
        XCTAssertNil(manager.read(address: 36, items: 2))
        XCTAssertNil(manager.read(address: 28, items: 2))
        XCTAssertNil(manager.read(address: 0, items: 10))
        XCTAssertEqual(manager.read(address: 0, items: 2), [0, 0xDEADBEEF])
    }

    /// Test `isValidAddress` function correctly checks address range.
    func testIsValidAddress() {
        XCTAssertTrue(manager.isValidAddress(address: 0))
        XCTAssertTrue(manager.isValidAddress(address: 4))
        XCTAssertTrue(manager.isValidAddress(address: 8))
        XCTAssertTrue(manager.isValidAddress(address: 28))
        XCTAssertFalse(manager.isValidAddress(address: 32))
        XCTAssertFalse(manager.isValidAddress(address: 9))
        XCTAssertFalse(manager.isValidAddress(address: 3))
        XCTAssertFalse(manager.isValidAddress(address: 36))
    }

    /// Test `wite` correctly writes data.
    func testWrite() {
        XCTAssertTrue(manager.write(address: 0, value: 0x8BADF00D))
        XCTAssertEqual(manager.memory[0], 0x8BADF00D)
        XCTAssertEqual(manager.memory[1], 0xDEADBEEF)
        XCTAssertFalse(manager.write(address: 1, value: 0x8BADF00D))
        XCTAssertFalse(manager.write(address: 32, value: 0x8BADF00D))
        XCTAssertTrue(manager.write(address: 16, value: 0x8BADF00D))
        XCTAssertEqual(manager.memory[4], 0x8BADF00D)
        XCTAssertEqual(manager.memory[3], 0)
        XCTAssertEqual(manager.memory[5], 0)
    }

}
