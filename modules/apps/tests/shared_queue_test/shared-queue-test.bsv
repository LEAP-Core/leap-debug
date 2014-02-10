//
// Copyright (C) 2013 MIT
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

//
// Implement shared queue (producer-consumer model) to test coherent 
// scratchpads' functionality and performance
//
module [CONNECTED_MODULE] mkSystem ();
    let tester <- (`SHARED_QUEUE_TEST_LOCK_MODE == 0)? mkSharedQueueTestNoLock() :
                  ((`SHARED_QUEUE_TEST_LOCK_MODE == 1)? mkSharedQueueTestWithHardLock() :
                  mkSharedQueueTestWithSoftLock());
endmodule

