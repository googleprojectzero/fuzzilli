// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

let Seconds = 1.0
let Minutes = 60.0 * Seconds
let Hours   = 60.0 * Minutes

/// API to schedule tasks to run after a specified interval and possibly repeatedly on the DispatchQueue of the associated fuzzer instance.
public class Timers {
    private var activeTimers = [DispatchSourceTimer]()
    private var isStopped = false
    private var queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    /// Schedule a task to run repeatedly in fixed time intervals.
    ///
    /// - Parameters:
    ///   - interval: The interval (in seconds) between two executions of the task.
    ///   - task: The task to execute.
    public func scheduleTask(every interval: TimeInterval, _ task: @escaping () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + interval, repeating: .seconds(Int(interval)))
        timer.setEventHandler(handler: task)
        timer.activate()
        activeTimers.append(timer)
    }

    /// Schedule a task to run a fixed number of times with the specified time interval between each execution.
    ///
    /// - Parameters:
    ///   - interval: The interval (in seconds) between two executions of the task.
    ///   - repetitions: The total number of executions of the task.
    ///   - task: The task to execute.
    public func scheduleTask(every interval: TimeInterval, repeat repetitions: Int, _ task: @escaping () -> Void) {
        guard repetitions > 0 else {
            return
        }

        runAfter(interval) {
            task()
            self.scheduleTask(every: interval, repeat: repetitions - 1, task)
        }
    }

    /// Executes the given task after the specified time interval.
    ///
    /// - Parameters:
    ///   - interval: The interval (in seconds) after which to execute the task.
    ///   - task: The task to execute.
    public func runAfter(_ interval: TimeInterval, _ task: @escaping () -> Void) {
        queue.asyncAfter(deadline: .now() + interval) {
            guard !self.isStopped else { return }
            task()
        }
    }

    /// Stops all active timers.
    public func stop() {
        for timer in activeTimers {
            timer.cancel()
        }
        activeTimers.removeAll()
        isStopped = true
    }
}
