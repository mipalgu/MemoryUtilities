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

public final class MemoryManager {

    let fileDescriptor: Int32

    let memory: UnsafeMutablePointer<UInt32>

    public let physicalAddress: size_t

    public let size: size_t

    public convenience init?(
        location: URL = URL(fileURLWithPath: "/dev/mem", isDirectory: false),
        physicalAddress: off_t,
        size: size_t,
        virtualAddress: UnsafeMutableRawPointer? = nil
    ) {
        guard physicalAddress >= 0, size > 0, location.isFileURL, !location.hasDirectoryPath else {
            return nil
        }
        let file = open(location.absoluteString, O_RDWR | O_SYNC)
        guard file != -1 else {
            return nil
        }
        guard let pointer = mmap(
            virtualAddress, size, PROT_READ | PROT_WRITE, MAP_SHARED_VALIDATE, file, physicalAddress
        ) else {
            close(file)
            return nil
        }
        let memory = pointer.assumingMemoryBound(to: UInt32.self)
        self.init(fileDescriptor: file, memory: memory, physicalAddress: size_t(physicalAddress), size: size)
    }

    init(fileDescriptor: Int32, memory: UnsafeMutablePointer<UInt32>, physicalAddress: size_t, size: size_t) {
        self.fileDescriptor = fileDescriptor
        self.memory = memory
        self.physicalAddress = physicalAddress
        self.size = size
    }

    deinit {
        _ = munmap(UnsafeMutableRawPointer(memory), size)
        close(self.fileDescriptor)
    }

    func isValidAddress(address: size_t) -> Bool {
        address >= self.physicalAddress && address < self.physicalAddress + self.size
    }

    public func read(address: size_t) -> UInt32? {
        guard self.isValidAddress(address: address) else {
            return nil
        }
        return self.memory[address]
    }

    public func read(address: size_t, items: Int) -> [UInt32]? {
        guard self.isValidAddress(address: address + size_t(items - 1)) else {
            return nil
        }
        return (0..<items).map { self.memory[address + size_t($0)] }
    }

    public func write(address: size_t, value: UInt32) -> Bool {
        guard self.isValidAddress(address: address) else {
            return false
        }
        self.memory[address] = value
        return true
    }

    public func write(address: size_t, values: [UInt32]) -> Bool {
        guard self.isValidAddress(address: address + size_t(values.count - 1)) else {
            return false
        }
        values.enumerated().forEach { self.memory[address + size_t($0)] = $1 }
        return true
    }

}