// MemoryManager.swift
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

import Foundation

/// A manager used to handle read and write operations to memory mapped files. This manager assumes 32-bit
/// alignment for the data stores and should not be used if this is not the case. This manager supports read
/// and write operations using 32-bit unsigned values.
public final class MemoryManager {

    /// A pointer to the memory-mapped region.
    @usableFromInline let memory: UnsafeMutablePointer<UInt32>

    /// The offset in bytes where user data begins. This value is always 32-bit aligned (i.e. multiples of 4)
    /// and represents the first accessible address in the data store.
    public let baseAddress: size_t

    /// The size of the data store in bytes. This value represents the number of bytes accessible to the user
    /// from the `baseAddress`. The last valid address is located at `baseAddress + size - 4` using 32-bit
    /// alignment. This value is always 32-bit aligned (i.e. multiples of 4) for this manager.
    public let size: size_t

    /// Create a manager that uses a memory-mapped file for data storage.
    /// - Parameters:
    ///   - location: The location of the file to be memory-mapped. This file must exist and be a regular
    /// file URL. This location will default to `/dev/mem`.
    ///   - baseAddress: The start address within the file that is accessible to the user. For the entire file
    /// to be accessible, this value should be 0. This value is always 32-bit aligned (i.e. multiples of 4).
    ///   - size: The size in bytes of the memory-mapped region within the file. This size should be 32-bit
    /// aligned and greater than 3 (atleast 4 bytes).
    ///   - virtualAddress: The address where the memory-mapped region should be mapped to. The linux kernel
    /// will choose a suitable address if this value is `nil`. There are no guarantees that the linux kernel
    /// will use this address. The virtual address needs to be page-aligned (i.e. multiples of
    /// `sysconf(_SC_PAGESIZE)`). It is more portable to keep this value as `nil`.
    @inlinable
    public convenience init?(
        location: URL = URL(fileURLWithPath: "/dev/mem", isDirectory: false),
        baseAddress: off_t,
        size: size_t,
        virtualAddress: UnsafeMutableRawPointer? = nil
    ) {
        guard
            baseAddress >= 0,
            baseAddress % 4 == 0,
            size >= 4,
            size % 4 == 0,
            location.isFileURL,
            !location.hasDirectoryPath
        else {
            return nil
        }
        let file = open(location.path, O_RDWR | O_SYNC)
        guard file != -1 else {
            return nil
        }
        defer { close(file) }
        guard
            let pointer = mmap(
                virtualAddress, size, PROT_READ | PROT_WRITE, MAP_SHARED, file, baseAddress
            ),
            pointer != MAP_FAILED
        else {
            return nil
        }
        let memory = pointer.assumingMemoryBound(to: UInt32.self)
        self.init(memory: memory, baseAddress: size_t(baseAddress), size: size)
    }

    /// Initialise the stored properties of this manager.
    /// - Parameters:
    ///   - memory: A pointer to the memory-mapped region of this data store.
    ///   - baseAddress: The offset where user data begins. This offset is relative to the `memory` base
    /// address and is in bytes.
    ///   - size: The number of bytes accessible to the user from the `baseAddress`. The last valid address
    /// is located at `memory.baseAddress + baseAddress + size - 4`. Please make sure the size is greater than
    /// 0 and 32-bit aligned (i.e. multiples of 4) before using this initialiser.
    @inlinable
    init(memory: UnsafeMutablePointer<UInt32>, baseAddress: size_t, size: size_t) {
        self.memory = memory
        self.baseAddress = baseAddress
        self.size = size
    }

    /// Remove the memory-mapped region.
    @inlinable
    deinit {
        _ = munmap(UnsafeMutableRawPointer(memory), size)
    }

    /// Check whether an address is valid for this data store.
    /// - Parameter address: The address to validate.
    /// - Returns: Whether the address is valid.
    @inlinable
    func isValidAddress(address: size_t) -> Bool {
        address % 4 == 0 && address >= self.baseAddress && address < self.baseAddress + self.size - 3
    }

    /// Reads a value located at an `address`.
    /// - Parameter address: The address to read from. This address must be 32-bit aligned (i.e. a multiple
    /// of 4).
    /// - Returns: The value located at `address`.
    /// - Warning: If the address is not 32-bit aligned, then this function will returned an undefined value.
    @inlinable
    func performRead(address: size_t) -> UInt32 {
        self.memory[baseAddress + (address - baseAddress) / 4]
    }

    /// Writes a `value` to an `address`.
    /// - Parameters:
    ///   - address: The address to write to. This address must be 32-bit aligned.
    ///   - value: The value to write to the address.
    /// - Warning: If the address is not 32-bit aligned, then this function will write to invalid memory.
    @inlinable
    func performWrite(address: size_t, value: UInt32) {
        self.memory[baseAddress + (address - baseAddress) / 4] = value
    }

    /// Read a value from an `address`.
    /// - Parameter address: The address to read from. This address must be 32-bit aligned (i.e. a multiple
    /// of 4) and represent the first byte of the value. This must also be valid in the memory-mapped region.
    /// - Returns: The value located at this address or `nil` if the address is invalid.
    @inlinable
    public func read(address: size_t) -> UInt32? {
        guard self.isValidAddress(address: address) else {
            return nil
        }
        return performRead(address: address)
    }

    /// Read multiple values starting at an `address`.
    /// - Parameters:
    ///   - address: The address of the first byte in the sequence. This address must be 32-bit aligned and 
    /// exist in the memory-mapped region. This address must also contain enough successors to read all
    /// values. The read operation will fail before any data is read if this is not the case.
    ///   - items: The number of `UInt32` values to read.
    /// - Returns: An array of `UInt32` values or `nil` if the address is invalid.
    @inlinable
    public func read(address: size_t, items: Int) -> [UInt32]? {
        guard
            items > 0,
            self.isValidAddress(address: address + size_t(items * 4 - 4)),
            self.isValidAddress(address: address)
        else {
            return nil
        }
        return (0..<items).map { performRead(address: address + size_t($0 * 4)) }
    }

    /// Write a `value` to an `address`.
    /// - Parameters:
    ///   - address: The address to write the value to. This address must be 32-bit aligned and exist within
    /// the memory-mapped region.
    ///   - value: The value to write to `address`.
    /// - Returns: Whether the write operation was successful.
    @discardableResult @inlinable
    public func write(address: size_t, value: UInt32) -> Bool {
        guard self.isValidAddress(address: address) else {
            return false
        }
        performWrite(address: address, value: value)
        return true
    }

    /// Write multiple `values` starting at an `address`.
    /// - Parameters:
    ///   - address: The address of the first byte to write to. This address must be 32-bit aligned and exist
    /// within the memory-mapped region. The first address must also contain enough successors to write all
    /// values. The write operation will fail before any data is written if this is not the case.
    ///   - values: The values to write starting at `address`.
    /// - Returns: Whether the write operation was successful.
    @discardableResult @inlinable
    public func write(address: size_t, values: [UInt32]) -> Bool {
        guard
            self.isValidAddress(address: address + size_t(values.count * 4 - 4)),
            self.isValidAddress(address: address)
        else {
            return false
        }
        values.enumerated().forEach { performWrite(address: address + size_t($0 * 4), value: $1) }
        return true
    }

}
